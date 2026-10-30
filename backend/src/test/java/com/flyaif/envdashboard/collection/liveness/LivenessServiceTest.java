package com.flyaif.envdashboard.collection.liveness;

import com.flyaif.envdashboard.catalog.ComponentRepository;
import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.LivenessStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;

/**
 * Drives the liveness sweep with a faked {@link LivenessProbe}: statuses are recorded per Component,
 * "changed at" moves only when the status does, a Component without a URL is cleared, and — because
 * the entity uses dynamic updates — a concurrent writer of other columns never wipes the result.
 * The race tests hold a probe open on a latch to force the interleavings deterministically.
 */
@SpringBootTest
class LivenessServiceTest {

    @Autowired
    private LivenessService liveness;

    @Autowired
    private EnvironmentRepository environments;

    @Autowired
    private ComponentRepository components;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @MockBean
    private LivenessProbe probe;

    @BeforeEach
    void clean() {
        environments.deleteAll();
    }

    private Long componentWithUrl(String url) {
        Environment env = new Environment("LIVENESS-" + url, null);
        Component component = new Component(ComponentRole.APP);
        component.setUrl(url);
        env.addComponent(component);
        return environments.save(env).getComponents().get(0).getId();
    }

    private Component reload(Long id) {
        return components.findById(id).orElseThrow();
    }

    @Test
    void sweepRecordsEachComponentsStatus() {
        given(probe.check("http://up/")).willReturn(LivenessCheck.up("HTTP 302"));
        given(probe.check("http://down/")).willReturn(LivenessCheck.down("HTTP 502"));
        given(probe.check("http://gone/")).willReturn(LivenessCheck.unreachable("no route to host"));
        Long up = componentWithUrl("http://up/");
        Long down = componentWithUrl("http://down/");
        Long gone = componentWithUrl("http://gone/");
        Long noUrl = componentWithUrl(" ");

        assertThat(liveness.checkAll()).isEqualTo(3); // nothing to clear on the URL-less one

        assertThat(reload(up).getLiveness()).isEqualTo(LivenessStatus.UP);
        assertThat(reload(up).getLivenessDetail()).isEqualTo("HTTP 302");
        assertThat(reload(up).getLivenessCheckedAt()).isNotNull();
        assertThat(reload(down).getLiveness()).isEqualTo(LivenessStatus.DOWN);
        assertThat(reload(gone).getLiveness()).isEqualTo(LivenessStatus.UNREACHABLE);
        assertThat(reload(noUrl).getLiveness()).isNull();
        assertThat(reload(noUrl).getLivenessCheckedAt()).isNull();
    }

    @Test
    void changedAtMovesOnlyWhenTheStatusDoes() throws InterruptedException {
        Long id = componentWithUrl("http://flappy/");
        given(probe.check("http://flappy/")).willReturn(LivenessCheck.up("HTTP 200"));
        liveness.checkAll();
        Instant firstSeen = reload(id).getLivenessChangedAt();

        Thread.sleep(5);
        liveness.checkAll();
        assertThat(reload(id).getLivenessChangedAt()).isEqualTo(firstSeen);
        assertThat(reload(id).getLivenessCheckedAt()).isAfter(firstSeen);

        given(probe.check("http://flappy/")).willReturn(LivenessCheck.down("connection refused"));
        liveness.checkAll();
        assertThat(reload(id).getLivenessChangedAt()).isAfter(firstSeen);
        assertThat(reload(id).getLivenessDetail()).isEqualTo("connection refused");
    }

    @Test
    void removingTheUrlClearsTheState() {
        Long id = componentWithUrl("http://was-here/");
        given(probe.check("http://was-here/")).willReturn(LivenessCheck.up("HTTP 200"));
        liveness.checkAll();

        TransactionTemplate tx = new TransactionTemplate(transactionManager);
        tx.executeWithoutResult(status -> reload(id).setUrl(null));
        liveness.checkAll();

        assertThat(reload(id).getLiveness()).isNull();
        assertThat(reload(id).getLivenessChangedAt()).isNull();
    }

    @Test
    void aConcurrentWriterOfOtherColumnsKeepsTheLivenessResult() {
        Long id = componentWithUrl("http://busy/");
        given(probe.check("http://busy/")).willReturn(LivenessCheck.down("HTTP 503"));

        // Stand-in for a Version Collection sweep: it loads the Component, the liveness sweep commits
        // meanwhile (in its own thread, hence its own transaction), then the collector saves.
        TransactionTemplate tx = new TransactionTemplate(transactionManager);
        tx.executeWithoutResult(status -> {
            Component stale = reload(id);
            CompletableFuture.runAsync(liveness::checkAll).join();
            stale.setVersion("9.9.9");
        });

        Component saved = reload(id);
        assertThat(saved.getVersion()).isEqualTo("9.9.9");
        assertThat(saved.getLiveness()).isEqualTo(LivenessStatus.DOWN);
    }

    @Test
    void aUrlEditedDuringACheckDropsTheResult() throws Exception {
        Long id = componentWithUrl("http://moving/");
        CountDownLatch probing = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        given(probe.check("http://moving/")).willAnswer(invocation -> {
            probing.countDown();
            release.await(5, TimeUnit.SECONDS);
            return LivenessCheck.up("HTTP 200");
        });

        CompletableFuture<Integer> manual = CompletableFuture.supplyAsync(() -> liveness.check(List.of(id)));
        assertThat(probing.await(5, TimeUnit.SECONDS)).isTrue();
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> reload(id).setUrl(null));
        release.countDown();

        assertThat(manual.get(5, TimeUnit.SECONDS)).isZero();
        assertThat(reload(id).getUrl()).isNull();
        assertThat(reload(id).getLiveness()).isNull();
    }

    @Test
    void aSlowCheckNeverOverwritesOneThatStartedLater() throws Exception {
        Long id = componentWithUrl("http://race/");
        CountDownLatch probing = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        AtomicInteger calls = new AtomicInteger();
        given(probe.check("http://race/")).willAnswer(invocation -> {
            if (calls.getAndIncrement() > 0) {
                return LivenessCheck.down("HTTP 502"); // the later, scheduled check
            }
            probing.countDown();
            release.await(5, TimeUnit.SECONDS);
            return LivenessCheck.up("HTTP 200");      // the earlier, slow manual check
        });

        CompletableFuture<Integer> slow = CompletableFuture.supplyAsync(() -> liveness.check(List.of(id)));
        assertThat(probing.await(5, TimeUnit.SECONDS)).isTrue();
        Thread.sleep(5);
        assertThat(liveness.checkAll()).isEqualTo(1);
        release.countDown();

        assertThat(slow.get(5, TimeUnit.SECONDS)).isZero();
        assertThat(reload(id).getLiveness()).isEqualTo(LivenessStatus.DOWN);
        assertThat(reload(id).getLivenessDetail()).isEqualTo("HTTP 502");
    }
}
