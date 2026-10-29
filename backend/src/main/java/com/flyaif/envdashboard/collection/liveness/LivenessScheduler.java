package com.flyaif.envdashboard.collection.liveness;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Runs the liveness sweep on a short configurable interval ({@code envdashboard.liveness.interval},
 * default one minute), switched off with {@code .scheduler-enabled=false} in local/test profiles and
 * never registered under the one-time {@code import} profile. It shares Spring's scheduler with the
 * much slower Version Collection sweep, which is why {@code spring.task.scheduling.pool.size} is
 * raised above one — otherwise a long collection would delay every liveness check behind it.
 */
@Component
@Profile("!import")
@ConditionalOnProperty(prefix = "envdashboard.liveness", name = "scheduler-enabled",
        havingValue = "true", matchIfMissing = true)
public class LivenessScheduler {

    private static final Logger log = LoggerFactory.getLogger(LivenessScheduler.class);

    private final LivenessService liveness;

    public LivenessScheduler(LivenessService liveness) {
        this.liveness = liveness;
    }

    @Scheduled(
            fixedDelayString = "${envdashboard.liveness.interval:PT1M}",
            initialDelayString = "${envdashboard.liveness.initial-delay:PT10S}")
    public void checkAll() {
        int recorded = liveness.checkAll();
        log.debug("Scheduled liveness check recorded {} component(s)", recorded);
    }
}
