package com.flyaif.envdashboard.collection;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Runs the Collection sweep on a configurable interval (scheduling itself is enabled in
 * {@link CollectionConfig}). Both the cadence and whether the scheduler runs at all are properties
 * ({@code envdashboard.collection.interval}, {@code .scheduler-enabled}), so prod polls automatically
 * while tests and local demos switch it off and drive Collection manually via the "refresh now" endpoint.
 */
@Component
@ConditionalOnProperty(prefix = "envdashboard.collection", name = "scheduler-enabled",
        havingValue = "true", matchIfMissing = true)
public class CollectionScheduler {

    private static final Logger log = LoggerFactory.getLogger(CollectionScheduler.class);

    private final CollectionService collection;

    public CollectionScheduler(CollectionService collection) {
        this.collection = collection;
    }

    @Scheduled(
            fixedDelayString = "${envdashboard.collection.interval:PT5M}",
            initialDelayString = "${envdashboard.collection.initial-delay:PT30S}")
    public void collectAll() {
        int collected = collection.refreshAll();
        log.info("Scheduled Collection refreshed {} component(s)", collected);
    }
}
