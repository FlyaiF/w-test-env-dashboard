package com.flyaif.envdashboard.collection;

import com.flyaif.envdashboard.collection.machine.JdbcAccessProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

import java.time.Clock;

/**
 * Wiring for the Version Collection context. Provides the {@link Clock} the collector uses to stamp
 * {@code lastCollectedAt} (injected so tests can pin time instead of reading the wall clock) and turns
 * on Spring scheduling. Scheduling being enabled here is harmless when no {@code @Scheduled} bean is
 * active — {@link CollectionScheduler} is itself property-gated, so tests/local simply omit it.
 */
@Configuration
@EnableScheduling
@EnableConfigurationProperties(JdbcAccessProperties.class)
public class CollectionConfig {

    @Bean
    public Clock collectionClock() {
        return Clock.systemUTC();
    }
}
