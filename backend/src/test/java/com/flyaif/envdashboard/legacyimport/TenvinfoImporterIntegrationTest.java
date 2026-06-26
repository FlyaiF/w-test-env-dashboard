package com.flyaif.envdashboard.legacyimport;

import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.ServerOs;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Full-stack import tests against H2 (Oracle mode): a complete legacy row maps to the right
 * aggregates, shared Server/Database rows are deduplicated, unusable rows are dropped and dirty
 * fields blanked (both reported), and dry-run writes nothing.
 */
@SpringBootTest
@Transactional
class TenvinfoImporterIntegrationTest {

    @Autowired
    private TenvinfoImporter importer;

    @Autowired
    private EnvironmentRepository environments;

    @Autowired
    private ServerRepository servers;

    @Autowired
    private DatabaseRepository databases;

    @BeforeEach
    void clean() {
        environments.deleteAll();
        servers.deleteAll();
        databases.deleteAll();
    }

    private LegacyEnvSource source(LegacyEnvRow... rows) {
        return () -> List.of(rows);
    }

    @Test
    void importsEnvironmentComponentServerAndDatabases() {
        LegacyEnvRow row = new LegacyEnvRow(
                100L, "环境 Alpha",
                "jdbc:oracle:thin:app/pw@10.0.2.5:1521/ORCL",   // E_YWDB
                "scott/tiger@10.0.2.6:1521/CFG",                // E_ZJDB
                "https://alpha.test/health",                    // E_URL
                "2.4.1",                                        // E_VERSION
                Instant.parse("2026-06-20T08:30:00Z"),          // E_UPDATETIME
                null,                                           // E_SEEURL
                "10.0.1.10:22&deploy/secret",                   // E_WEBSERVERADDR
                "/var/log/app.log",                             // E_WEBLOGPATH
                "QA 主测试环境",                                  // E_MEMO
                "oracle");                                      // E_DBTYPE

        ImportReport report = importer.run(source(row), false);

        assertThat(report.getImportedEnvironments()).containsExactly(100L);
        assertThat(report.getComponentsCreated()).isEqualTo(1);
        assertThat(report.getServersCreated()).isEqualTo(1);
        assertThat(report.getDatabasesCreated()).isEqualTo(2);

        List<Environment> all = environments.findAll();
        assertThat(all).hasSize(1);
        Environment env = all.get(0);
        assertThat(env.getName()).isEqualTo("环境 Alpha");
        assertThat(env.getMemo()).isEqualTo("QA 主测试环境");
        assertThat(env.getComponents()).hasSize(1);

        Component component = env.getComponents().get(0);
        assertThat(component.getRole()).isEqualTo(ComponentRole.GATEWAY);
        assertThat(component.getVersion()).isEqualTo("2.4.1");
        assertThat(component.getDeployTime()).isEqualTo(Instant.parse("2026-06-20T08:30:00Z"));
        assertThat(component.getLogLocation()).isEqualTo("/var/log/app.log");
        assertThat(component.getUrl()).isEqualTo("https://alpha.test/health");
        assertThat(component.getServerId()).isNotNull();
        assertThat(component.getDatabaseIds()).hasSize(2);

        Server server = servers.findById(component.getServerId()).orElseThrow();
        assertThat(server.getHost()).isEqualTo("10.0.1.10");
        assertThat(server.getOs()).isEqualTo(ServerOs.LINUX);
        assertThat(server.getSsh().getHost()).isEqualTo("10.0.1.10");
        assertThat(server.getSsh().getPort()).isEqualTo(22);
        assertThat(server.getSsh().getUsername()).isEqualTo("deploy");

        List<Database> dbs = databases.findAll();
        assertThat(dbs).hasSize(2);
        Database business = dbs.stream().filter(d -> d.getRole().equals("business")).findFirst().orElseThrow();
        assertThat(business.getType()).isEqualTo(DatabaseType.ORACLE);
        assertThat(business.getConnection().getHost()).isEqualTo("10.0.2.5");
        assertThat(business.getConnection().getPort()).isEqualTo(1521);
        assertThat(business.getConnection().getServiceName()).isEqualTo("ORCL");
        assertThat(business.getConnection().getUsername()).isEqualTo("app");

        // The password was present but deliberately not persisted (brokered in slice 06).
        assertThat(report.getCredentialsSeen()).isGreaterThan(0);
    }

    @Test
    void deduplicatesSharedServerAndDatabaseAcrossRows() {
        LegacyEnvRow first = new LegacyEnvRow(1L, "Env One",
                "app/pw@shared-db:1521/ORCL", null, null, null, null, null,
                "shared-host:22&deploy/pw", null, null, "oracle");
        LegacyEnvRow second = new LegacyEnvRow(2L, "Env Two",
                "app/pw@shared-db:1521/ORCL", null, null, null, null, null,
                "shared-host:22&deploy/pw", null, null, "oracle");

        ImportReport report = importer.run(source(first, second), false);

        assertThat(report.getImportedEnvironments()).containsExactly(1L, 2L);
        assertThat(servers.findAll()).hasSize(1);
        assertThat(databases.findAll()).hasSize(1);
        assertThat(report.getServersCreated()).isEqualTo(1);
        assertThat(report.getServersReused()).isEqualTo(1);
        assertThat(report.getDatabasesCreated()).isEqualTo(1);
        assertThat(report.getDatabasesReused()).isEqualTo(1);

        Long sharedServerId = servers.findAll().get(0).getId();
        Long sharedDbId = databases.findAll().get(0).getId();
        for (Environment env : environments.findAll()) {
            Component component = env.getComponents().get(0);
            assertThat(component.getServerId()).isEqualTo(sharedServerId);
            assertThat(component.getDatabaseIds()).containsExactly(sharedDbId);
        }
    }

    @Test
    void dropsAndReportsRowWithoutName() {
        LegacyEnvRow nameless = new LegacyEnvRow(7L, "  ",
                "app/pw@db:1521/ORCL", null, null, null, null, null, null, null, null, "oracle");

        ImportReport report = importer.run(source(nameless), false);

        assertThat(report.getImportedEnvironments()).isEmpty();
        assertThat(report.getDroppedRows()).hasSize(1);
        assertThat(report.getDroppedRows().get(0).eNo()).isEqualTo(7L);
        assertThat(environments.findAll()).isEmpty();
        assertThat(databases.findAll()).isEmpty();
    }

    @Test
    void blanksAndReportsDirtyWebServerAddrButKeepsRow() {
        LegacyEnvRow row = new LegacyEnvRow(9L, "Env Dirty",
                null, null, "https://dirty.test", "1.0", null, null,
                ":::garbage",   // unparseable E_WEBSERVERADDR (no host)
                null, null, "oracle");

        ImportReport report = importer.run(source(row), false);

        assertThat(report.getImportedEnvironments()).containsExactly(9L);
        assertThat(report.getBlankedFields())
                .anySatisfy(b -> assertThat(b.field()).isEqualTo("E_WEBSERVERADDR"));
        assertThat(servers.findAll()).isEmpty();

        Component component = environments.findAll().get(0).getComponents().get(0);
        assertThat(component.getServerId()).isNull();
        assertThat(component.getUrl()).isEqualTo("https://dirty.test");
    }

    @Test
    void refusesToWriteIntoANonEmptyTarget() {
        LegacyEnvRow row = new LegacyEnvRow(1L, "Env One",
                "app/pw@db:1521/ORCL", null, null, null, null, null, null, null, null, "oracle");
        importer.run(source(row), false);

        // A second apply against the now-populated schema must refuse rather than duplicate.
        LegacyEnvRow again = new LegacyEnvRow(2L, "Env Two",
                "app/pw@db:1521/ORCL", null, null, null, null, null, null, null, null, "oracle");
        assertThatThrownBy(() -> importer.run(source(again), false))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("not empty");

        assertThat(environments.findAll()).hasSize(1);
    }

    @Test
    void doesNotEchoCredentialsIntoTheReport() {
        LegacyEnvRow row = new LegacyEnvRow(3L, "Env Secret",
                "user/topsecret@:::nohost",          // unparseable DB slot carrying a password
                null, null, null, null, null,
                "::&deploy/sshsecret",                // unparseable web addr carrying a password
                null, null, "oracle");

        ImportReport report = importer.run(source(row), true);

        assertThat(report.getBlankedFields()).isNotEmpty();
        for (ImportReport.BlankedField blanked : report.getBlankedFields()) {
            assertThat(blanked.reason()).doesNotContain("topsecret").doesNotContain("sshsecret");
        }
        assertThat(report.render()).doesNotContain("topsecret").doesNotContain("sshsecret");
    }

    @Test
    void dryRunWritesNothingButStillReports() {
        LegacyEnvRow row = new LegacyEnvRow(5L, "Env Preview",
                "app/pw@db:1521/ORCL", null, "https://preview.test", "1.2.3",
                Instant.parse("2026-06-01T00:00:00Z"), null,
                "host:22&u/p", "/log/path", "memo", "oracle");

        ImportReport report = importer.run(source(row), true);

        assertThat(report.isDryRun()).isTrue();
        assertThat(report.getImportedEnvironments()).containsExactly(5L);
        assertThat(report.getComponentsCreated()).isEqualTo(1);
        assertThat(report.getServersCreated()).isEqualTo(1);
        assertThat(report.getDatabasesCreated()).isEqualTo(1);

        assertThat(environments.findAll()).isEmpty();
        assertThat(servers.findAll()).isEmpty();
        assertThat(databases.findAll()).isEmpty();
    }
}
