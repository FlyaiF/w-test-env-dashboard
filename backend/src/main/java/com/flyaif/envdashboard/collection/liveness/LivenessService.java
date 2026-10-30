package com.flyaif.envdashboard.collection.liveness;

import com.flyaif.envdashboard.catalog.ComponentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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
 * cleared — there is nothing to judge it by. Results are ordered by when their check started: the
 * newest observation wins regardless of which check finishes last.
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
        // Own transactions even when called from inside one, so results commit as soon as they exist.
        this.transactions = new TransactionTemplate(transactionManager);
        this.transactions.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        this.batchTimeout = properties.getConnectTimeout()
                .plus(properties.getRequestTimeout())
                .plusSeconds(5);
    }

    /** Scheduled sweep across every Component; returns the number of results recorded. */
    public int checkAll() {
        return checkAndRecord(transactions.execute(status -> snapshot(components.findAll())));
    }

    /** Checks the given Components now (manual refresh); returns the number of results recorded. */
    public int check(Collection<Long> componentIds) {
        return checkAndRecord(transactions.execute(status -> snapshot(components.findAllById(componentIds))));
    }

    private static Map<Long, Component> snapshot(List<Component> loaded) {
        Map<Long, Component> byId = new HashMap<>();
        loaded.forEach(c -> byId.put(c.getId(), c));
        return byId;
    }

    /**
     * Probes outside any transaction, then commits each result promptly in its own short one. Each
     * write is conditional (see {@link ComponentRepository#recordLiveness}): it is dropped if the URL
     * was edited while the check ran, or if a check that started later has already been recorded —
     * so a slow manual refresh and the scheduled sweep can never put an older observation back.
     */
    private int checkAndRecord(Map<Long, Component> snapshot) {
        Instant observedAt = clock.instant();
        Map<Long, String> urls = new HashMap<>();
        snapshot.forEach((id, c) -> urls.put(id, c.getUrl()));
        Map<Long, LivenessCheck> results = probeAll(urls);
        int recorded = 0;
        for (Component before : snapshot.values()) {
            try {
                Integer written = transactions.execute(status -> record(before, results.get(before.getId()), observedAt));
                recorded += written == null ? 0 : written;
            } catch (RuntimeException ex) {
                log.warn("Liveness failed to save component {}: {}", before.getId(), ex.getMessage());
            }
        }
        return recorded;
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

    private int record(Component before, LivenessCheck check, Instant observedAt) {
        String url = before.getUrl();
        if (url == null || url.isBlank()) {
            return components.clearLiveness(before.getId());
        }
        if (check == null) {
            return 0; // interrupted before this Component was probed; keep the previous state
        }
        int written = components.recordLiveness(
                before.getId(), url, check.status(), truncate(check.detail()), observedAt);
        if (written > 0 && before.getLiveness() != null && before.getLiveness() != check.status()) {
            log.info("Component {} liveness {} -> {} ({})",
                    before.getId(), before.getLiveness(), check.status(), check.detail());
        }
        return written;
    }

    private static String truncate(String detail) {
        if (detail == null || detail.length() <= MAX_DETAIL_LENGTH) {
            return detail;
        }
        return detail.substring(0, MAX_DETAIL_LENGTH);
    }
}
