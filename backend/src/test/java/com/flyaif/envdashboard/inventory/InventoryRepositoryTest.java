package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.ServerOs;
import com.flyaif.envdashboard.inventory.domain.SshAccess;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Exercises the Resource Inventory aggregates and the Component->Server/Database link columns against
 * H2 (Oracle mode), proving the V2 migration and the shared-resource mapping.
 */
@DataJpaTest
class InventoryRepositoryTest {

    @Autowired
    private ServerRepository servers;

    @Autowired
    private DatabaseRepository databases;

    @Autowired
    private EnvironmentRepository environments;

    @Autowired
    private TestEntityManager em;

    @Test
    void persistsServerWithEmbeddedSshAccess() {
        Server server = new Server("host-01", ServerOs.LINUX, new SshAccess("10.0.0.1", 22, "deploy"));
        Long id = servers.save(server).getId();
        em.flush();
        em.clear();

        Server reloaded = servers.findById(id).orElseThrow();
        assertThat(reloaded.getHost()).isEqualTo("host-01");
        assertThat(reloaded.getOs()).isEqualTo(ServerOs.LINUX);
        assertThat(reloaded.getSsh().getHost()).isEqualTo("10.0.0.1");
        assertThat(reloaded.getSsh().getPort()).isEqualTo(22);
        assertThat(reloaded.getSsh().getUsername()).isEqualTo("deploy");
    }

    @Test
    void persistsDatabaseWithEmbeddedConnectionDescriptor() {
        Database db = new Database("business", DatabaseType.ORACLE,
                new ConnectionDescriptor("10.0.0.5", 1521, "ORCL", "app"));
        Long id = databases.save(db).getId();
        em.flush();
        em.clear();

        Database reloaded = databases.findById(id).orElseThrow();
        assertThat(reloaded.getRole()).isEqualTo("business");
        assertThat(reloaded.getType()).isEqualTo(DatabaseType.ORACLE);
        assertThat(reloaded.getConnection().getServiceName()).isEqualTo("ORCL");
        assertThat(reloaded.getConnection().getPort()).isEqualTo(1521);
    }

    @Test
    void componentReferencesServerAndDatabasesById() {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));
        Database db1 = databases.save(new Database("business", DatabaseType.ORACLE, null));
        Database db2 = databases.save(new Database("config", DatabaseType.DAMENG, null));
        em.flush();

        Environment env = new Environment("ENV-A", null);
        Component app = new Component(ComponentRole.APP);
        app.setServerId(server.getId());
        app.setDatabaseIds(Set.of(db1.getId(), db2.getId()));
        env.addComponent(app);
        Long envId = environments.save(env).getId();
        em.flush();
        em.clear();

        Component reloaded = environments.findById(envId).orElseThrow().getComponents().get(0);
        assertThat(reloaded.getServerId()).isEqualTo(server.getId());
        assertThat(reloaded.getDatabaseIds()).containsExactlyInAnyOrder(db1.getId(), db2.getId());
    }

    @Test
    void deletingEnvironmentLeavesSharedResourcesIntact() {
        Server server = servers.save(new Server("host-01", ServerOs.LINUX, null));
        Database db = databases.save(new Database("business", DatabaseType.ORACLE, null));
        em.flush();

        Environment env = new Environment("ENV-A", null);
        Component app = new Component(ComponentRole.APP);
        app.setServerId(server.getId());
        app.setDatabaseIds(Set.of(db.getId()));
        env.addComponent(app);
        Long envId = environments.save(env).getId();
        em.flush();

        environments.deleteById(envId);
        em.flush();
        em.clear();

        // The shared Server/Database survive the Environment's deletion (independent lifecycle).
        assertThat(servers.findById(server.getId())).isPresent();
        assertThat(databases.findById(db.getId())).isPresent();
        // The use-link rows are gone with the Component.
        Number links = (Number) em.getEntityManager()
                .createNativeQuery("select count(*) from component_database")
                .getSingleResult();
        assertThat(links.longValue()).isZero();
    }
}
