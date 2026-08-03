package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.access.SecretStore;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class LocalSeedDataProfileTest {

    @Test
    void localImportProfileDoesNotRegisterDemoSeedRunner() {
        try (AnnotationConfigApplicationContext context = contextWithProfiles("local", "import")) {
            assertThat(context.getBeansOfType(LocalSeedData.class)).isEmpty();
        }
    }

    @Test
    void localProfileStillRegistersDemoSeedRunner() {
        try (AnnotationConfigApplicationContext context = contextWithProfiles("local")) {
            assertThat(context.getBeansOfType(LocalSeedData.class)).hasSize(1);
        }
    }

    private AnnotationConfigApplicationContext contextWithProfiles(String... profiles) {
        AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext();
        context.getEnvironment().setActiveProfiles(profiles);
        context.registerBean(EnvironmentRepository.class, () -> mock(EnvironmentRepository.class));
        context.registerBean(ServerRepository.class, () -> mock(ServerRepository.class));
        context.registerBean(DatabaseRepository.class, () -> mock(DatabaseRepository.class));
        context.registerBean(SecretStore.class, () -> mock(SecretStore.class));
        context.register(LocalSeedData.class);
        context.refresh();
        return context;
    }
}
