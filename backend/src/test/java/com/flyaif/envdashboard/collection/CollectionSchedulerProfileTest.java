package com.flyaif.envdashboard.collection;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class CollectionSchedulerProfileTest {

    @Test
    void importProfileDoesNotRegisterBackgroundCollector() {
        try (AnnotationConfigApplicationContext context = contextWithProfiles("prod", "import")) {
            assertThat(context.getBeansOfType(CollectionScheduler.class)).isEmpty();
        }
    }

    @Test
    void normalProductionProfileStillRegistersBackgroundCollector() {
        try (AnnotationConfigApplicationContext context = contextWithProfiles("prod")) {
            assertThat(context.getBeansOfType(CollectionScheduler.class)).hasSize(1);
        }
    }

    private AnnotationConfigApplicationContext contextWithProfiles(String... profiles) {
        AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext();
        context.getEnvironment().setActiveProfiles(profiles);
        context.registerBean(CollectionService.class, () -> mock(CollectionService.class));
        context.register(CollectionScheduler.class);
        context.refresh();
        return context;
    }
}
