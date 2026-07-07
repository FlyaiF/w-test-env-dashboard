package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.CollectionStatus;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Exercises the Environment-owns-Components mapping and the V1 migration against H2 (Oracle mode).
 */
@DataJpaTest
class EnvironmentRepositoryTest {

    @Autowired
    private EnvironmentRepository repository;

    @Autowired
    private TestEntityManager em;

    @Test
    void persistsEnvironmentWithItsComponentsAndAssignsSequenceIds() {
        Environment env = new Environment("ENV-A", "first env");
        Component gateway = new Component(ComponentRole.GATEWAY);
        gateway.setVersion("1.2.3");
        gateway.setVersionUpdatedAt(Instant.parse("2026-01-02T03:04:05Z"));
        gateway.setLogLocation("/var/log/gateway.log");
        gateway.setListenPort(8080);
        gateway.setProtocol("https");
        gateway.setUrl("https://gw.example/health");
        env.addComponent(gateway);
        env.addComponent(new Component(ComponentRole.APP));

        Environment saved = repository.save(env);
        em.flush();
        em.clear();

        assertThat(saved.getId()).isNotNull();

        Environment reloaded = repository.findById(saved.getId()).orElseThrow();
        assertThat(reloaded.getName()).isEqualTo("ENV-A");
        assertThat(reloaded.getMemo()).isEqualTo("first env");
        assertThat(reloaded.getComponents()).hasSize(2);

        Component reloadedGateway = reloaded.getComponents().stream()
                .filter(c -> c.getRole() == ComponentRole.GATEWAY)
                .findFirst().orElseThrow();
        assertThat(reloadedGateway.getId()).isNotNull();
        assertThat(reloadedGateway.getVersion()).isEqualTo("1.2.3");
        assertThat(reloadedGateway.getVersionUpdatedAt()).isEqualTo(Instant.parse("2026-01-02T03:04:05Z"));
        assertThat(reloadedGateway.getListenPort()).isEqualTo(8080);
        // Collection fields stay null until slice 05.
        assertThat(reloadedGateway.getCollectionStatus()).isNull();
        assertThat(reloadedGateway.getVersionProbe()).isNull();
        assertThat(reloadedGateway.getLastCollectedAt()).isNull();
    }

    @Test
    void persistsCollectionFieldsAsLegibleStringsWhenSet() {
        Environment env = new Environment("ENV-B", null);
        Component app = new Component(ComponentRole.APP);
        app.setCollectionStatus(CollectionStatus.OK);
        app.setVersionProbe(VersionProbeKind.DB);
        app.setLastCollectedAt(Instant.parse("2026-02-03T04:05:06Z"));
        env.addComponent(app);

        Long id = repository.save(env).getId();
        em.flush();
        em.clear();

        Component reloaded = repository.findById(id).orElseThrow().getComponents().get(0);
        assertThat(reloaded.getCollectionStatus()).isEqualTo(CollectionStatus.OK);
        assertThat(reloaded.getVersionProbe()).isEqualTo(VersionProbeKind.DB);
        assertThat(reloaded.getLastCollectedAt()).isEqualTo(Instant.parse("2026-02-03T04:05:06Z"));
    }

    @Test
    void cascadeDeletesComponentsWithTheirEnvironment() {
        Environment env = new Environment("ENV-C", null);
        env.addComponent(new Component(ComponentRole.UI));
        Long id = repository.save(env).getId();
        em.flush();

        repository.deleteById(id);
        em.flush();
        em.clear();

        assertThat(repository.findById(id)).isEmpty();
        Long orphanComponents = em.getEntityManager()
                .createQuery("select count(c) from Component c", Long.class)
                .getSingleResult();
        assertThat(orphanComponents).isZero();
    }

    @Test
    void findAllReturnsEachEnvironmentWithItsComponents() {
        Environment a = new Environment("ENV-A", null);
        a.addComponent(new Component(ComponentRole.GATEWAY));
        Environment b = new Environment("ENV-B", null);
        b.addComponent(new Component(ComponentRole.APP));
        b.addComponent(new Component(ComponentRole.UI));
        repository.save(a);
        repository.save(b);
        em.flush();
        em.clear();

        List<Environment> all = repository.findAll();
        assertThat(all).hasSize(2);
        assertThat(all).allSatisfy(e -> assertThat(e.getComponents()).isNotEmpty());
    }
}
