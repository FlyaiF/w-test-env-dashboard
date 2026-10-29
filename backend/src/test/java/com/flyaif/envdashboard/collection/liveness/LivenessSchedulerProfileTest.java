package com.flyaif.envdashboard.collection.liveness;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class LivenessSchedulerProfileTest {

    @Test
    void importProfileDoesNotRegisterBackgroundLivenessCheck() {
        try (AnnotationConfigApplicationContext context = contextWithProfiles("prod", "import")) {
            assertThat(context.getBeansOfType(LivenessScheduler.class)).isEmpty();
        }
    }

    @Test
    void normalProductionProfileRegistersBackgroundLivenessCheck() {
        try (AnnotationConfigApplicationContext context = contextWithProfiles("prod")) {
            assertThat(context.getBeansOfType(LivenessScheduler.class)).hasSize(1);
        }
    }

    private AnnotationConfigApplicationContext contextWithProfiles(String... profiles) {
        AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext();
        context.getEnvironment().setActiveProfiles(profiles);
        context.registerBean(LivenessService.class, () -> mock(LivenessService.class));
        context.register(LivenessScheduler.class);
        context.refresh();
        return context;
    }
}
