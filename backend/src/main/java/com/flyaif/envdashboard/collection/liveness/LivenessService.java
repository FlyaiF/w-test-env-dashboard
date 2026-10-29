package com.flyaif.envdashboard.collection.liveness;

import com.flyaif.envdashboard.catalog.ComponentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

/**
 * Records each Component's running state (UP / DOWN / UNREACHABLE) by checking its URL through the
 * {@link LivenessProbe}. Every URL is checked in parallel on virtual threads, so a sweep takes about
 * as long as its slowest check rather than the sum of them. A Component without a URL has its state
 * cleared — there is nothing to judge it by.
 *
 * <p>Independent of Version Collection on purpose: it is cheap, runs far more often, and answers a
 * different question ("is it serving?" rather than "which version is live?").
 */
@Service
public class LivenessService {

    private static final Logger log = LoggerFactory.getLogger(LivenessService.class);

    /** Longest detail persisted; matches the liveness_detail column width. */
    private static final int MAX_DETAIL_LENGTH = 500;

    private final ComponentRepository components;
    private final LivenessProbe probe;
    private final Clock clock;
    private final TransactionTemplate transactions;

    /** Backstop for a whole parallel batch, should a probe ever ignore its own timeouts. */
    private final Duration batchTimeout;

    public LivenessService(ComponentRepository components,
                           LivenessProbe probe,
                           Clock clock,
                           PlatformTransactionManager transactionManager,
                           LivenessProperties properties) {
        this.components = components;
        this.probe = probe;
        this.clock = clock;
        this.transactions = new TransactionTemplate(transactionManager);
        this.batchTimeout = properties.getConnectTimeout()
                .plus(properties.getRequestTimeout())
                .plusSeconds(5);
    }

    /**
     * Scheduled sweep across every Component; returns the number recorded. Probing happens outside
     * any transaction, then each Component is saved in its own short one. A Component whose URL was
     * edited while its check ran is skipped — the next sweep checks the new URL.
     */
    public int checkAll() {
        Map<Long, String> urls = transactions.execute(status -> {
            Map<Long, String> byId = new HashMap<>();
            components.findAll().forEach(c -> byId.put(c.getId(), c.getUrl()));
            return byId;
        });
        Map<Long, LivenessCheck> results = probeAll(urls);
        int recorded = 0;
        for (Map.Entry<Long, String> entry : urls.entrySet()) {
            Long id = entry.getKey();
            try {
                Boolean saved = transactions.execute(status -> components.findById(id)
                        .filter(c -> Objects.equals(c.getUrl(), entry.getValue()))
                        .map(c -> {
                            record(c, results.get(id));
                            return true;
                        })
                        .orElse(false));
                if (Boolean.TRUE.equals(saved)) {
                    recorded++;
                }
            } catch (RuntimeException ex) {
                log.warn("Liveness failed to save component {}: {}", id, ex.getMessage());
            }
        }
        return recorded;
    }

    /** Check the given managed Components now, within the caller's transaction (manual refresh). */
    public void check(Collection<Component> managed) {
        Map<Long, String> urls = new HashMap<>();
        managed.forEach(c -> urls.put(c.getId(), c.getUrl()));
        Map<Long, LivenessCheck> results = probeAll(urls);
        managed.forEach(c -> record(c, results.get(c.getId())));
    }

    /** Probes every non-blank URL in parallel; a blank URL maps to no entry (clear the state). */
    private Map<Long, LivenessCheck> probeAll(Map<Long, String> urls) {
        List<Long> ids = new ArrayList<>();
        List<Callable<LivenessCheck>> tasks = new ArrayList<>();
        urls.forEach((id, url) -> {
            if (url != null && !url.isBlank()) {
                ids.add(id);
                tasks.add(() -> probe.check(url));
            }
        });
        Map<Long, LivenessCheck> results = new HashMap<>();
        if (tasks.isEmpty()) {
            return results;
        }
        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<LivenessCheck>> futures =
                    executor.invokeAll(tasks, batchTimeout.toMillis(), TimeUnit.MILLISECONDS);
            for (int i = 0; i < futures.size(); i++) {
                results.put(ids.get(i), outcome(futures.get(i)));
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return results;
    }

    private static LivenessCheck outcome(Future<LivenessCheck> future) {
        if (future.isCancelled()) {
            return LivenessCheck.unreachable("check timed out");
        }
        try {
            LivenessCheck check = future.get();
            return check != null ? check : LivenessCheck.unreachable("no result");
        } catch (ExecutionException e) {
            return LivenessCheck.unreachable("check failed: " + e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return LivenessCheck.unreachable("check interrupted");
        }
    }

    private void record(Component component, LivenessCheck check) {
        String url = component.getUrl();
        if (url == null || url.isBlank()) {
            component.clearLiveness();
            return;
        }
        if (check == null) {
            return; // interrupted before this Component was probed; keep the previous state
        }
        if (component.getLiveness() != null && component.getLiveness() != check.status()) {
            log.info("Component {} liveness {} -> {} ({})",
                    component.getId(), component.getLiveness(), check.status(), check.detail());
        }
        component.recordLiveness(check.status(), truncate(check.detail()), clock.instant());
    }

    private static String truncate(String detail) {
        if (detail == null || detail.length() <= MAX_DETAIL_LENGTH) {
            return detail;
        }
        return detail.substring(0, MAX_DETAIL_LENGTH);
    }
}
