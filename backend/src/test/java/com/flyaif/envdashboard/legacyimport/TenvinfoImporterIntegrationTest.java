package com.flyaif.envdashboard.legacyimport;

import com.flyaif.envdashboard.access.AccessBrokerService;
import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.collection.CollectionService;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
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
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

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

    @Autowired
    private AccessBrokerService broker;

    @Autowired
    private CollectionService collection;

    @MockBean
    private MachineAccess machineAccess;

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
        assertThat(component.getRole()).isEqualTo(ComponentRole.UNSPECIFIED);
        assertThat(component.getVersion()).isEqualTo("2.4.1");
        assertThat(component.getVersionUpdatedAt()).isEqualTo(Instant.parse("2026-06-20T08:30:00Z"));
        assertThat(component.getLogLocation()).isEqualTo("/var/log/app.log");
        assertThat(component.getUrl()).isEqualTo("https://alpha.test/health");
        assertThat(component.getVersionProbe()).isEqualTo(VersionProbeKind.DB);
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

        // The legacy passwords are migrated into the encrypted broker (ADR-0008), reachable only via
        // on-demand brokering — never along the Inventory read DTOs asserted above.
        assertThat(report.getCredentialsSeen()).isGreaterThan(0);
        assertThat(broker.brokerServerCredential(component.getServerId()).secret()).isEqualTo("secret");
        assertThat(broker.brokerDatabaseCredential(business.getId()).secret()).isEqualTo("pw");
        assertThat(report.render())
                .contains("secrets encrypted in the access broker")
                .doesNotContain("Credentials seen but NOT stored");
    }

    @Test
    void migratedBusinessDatabaseDispatchesDbCollectionAndRefreshesVersion() {
        Instant refreshedAt = Instant.parse("2026-07-01T03:04:05Z");
        given(machineAccess.queryScalar(any(Database.class), anyString())).willReturn(" 5.6.7 ");
        given(machineAccess.queryInstant(any(Database.class), anyString())).willReturn(refreshedAt);

        LegacyEnvRow row = new LegacyEnvRow(101L, "环境 Collect",
                "app/pw@business-db:1521/ORCL", null, null, "old-version", null, null,
                null, null, null, "oracle");

        importer.run(source(row), false);
        Environment imported = environments.findAll().get(0);
        assertThat(imported.getComponents().get(0).getVersionProbe()).isEqualTo(VersionProbeKind.DB);

        EnvironmentDto refreshed = collection.refresh(imported.getId());
        ComponentDto component = refreshed.components().get(0);
        assertThat(component.collectionStatus()).isEqualTo("OK");
        assertThat(component.version()).isEqualTo("5.6.7");
        assertThat(component.versionUpdatedAt()).isEqualTo(refreshedAt);
        verify(machineAccess).queryScalar(
                argThat(database -> Database.BUSINESS_ROLE.equals(database.getRole())), anyString());
        verify(machineAccess).queryInstant(
                argThat(database -> Database.BUSINESS_ROLE.equals(database.getRole())), anyString());
    }

    @Test
    void importsDecodedOceanBaseQueryCredentialsAndRebuildsCanonicalUrl() {
        LegacyEnvRow row = new LegacyEnvRow(104L, "环境 OceanBase",
                "jdbc:oceanbase:oracle://ob.example:2881/APP"
                        + "?connectTimeout=5000&user=app%40oracle_tenant&password=p%2Bss%26word",
                null, null, null, null, null, null, null, null, "oceanbase");

        importer.run(source(row), false);

        Database database = databases.findAll().get(0);
        assertThat(database.getType()).isEqualTo(DatabaseType.OCEANBASE);
        assertThat(database.getConnection().getUsername()).isEqualTo("app@oracle_tenant");
        assertThat(broker.brokerDatabaseCredential(database.getId()).secret()).isEqualTo("p+ss&word");
        assertThat(broker.brokerDatabaseCredential(database.getId()).jdbcUrl())
                .isEqualTo("jdbc:oceanbase://ob.example:2881/APP");
    }

    @Test
    void defaultsOmittedEnginePortsAndReportsTheNormalization() {
        LegacyEnvRow oracle = new LegacyEnvRow(105L, "环境 Oracle Default Port",
                "jdbc:oracle:thin:app/pw@oracle-db/ORCL", null, null, null, null, null,
                null, null, null, "oracle");
        LegacyEnvRow dameng = new LegacyEnvRow(106L, "环境 Dameng Default Port",
                "app/pw@dameng-db/DMDB", null, null, null, null, null,
                null, null, null, "dameng");
        LegacyEnvRow oceanBase = new LegacyEnvRow(107L, "环境 OceanBase Default Port",
                "jdbc:oceanbase:oracle://ocean-db/APP?user=app&password=pw", null,
                null, null, null, null, null, null, null, "oceanbase");

        ImportReport report = importer.run(source(oracle, dameng, oceanBase), false);

        List<Database> imported = databases.findAll();
        Database oracleDb = imported.stream()
                .filter(database -> database.getType() == DatabaseType.ORACLE).findFirst().orElseThrow();
        Database damengDb = imported.stream()
                .filter(database -> database.getType() == DatabaseType.DAMENG).findFirst().orElseThrow();
        Database oceanBaseDb = imported.stream()
                .filter(database -> database.getType() == DatabaseType.OCEANBASE).findFirst().orElseThrow();

        assertThat(oracleDb.getConnection().getPort()).isEqualTo(1521);
        assertThat(damengDb.getConnection().getPort()).isEqualTo(5236);
        assertThat(oceanBaseDb.getConnection().getPort()).isEqualTo(2881);
        assertThat(broker.brokerDatabaseCredential(oracleDb.getId()).jdbcUrl())
                .isEqualTo("jdbc:oracle:thin:@//oracle-db:1521/ORCL");
        assertThat(broker.brokerDatabaseCredential(damengDb.getId()).jdbcUrl())
                .isEqualTo("jdbc:dm://dameng-db:5236");
        assertThat(broker.brokerDatabaseCredential(oceanBaseDb.getId()).jdbcUrl())
                .isEqualTo("jdbc:oceanbase://ocean-db:2881/APP");
        assertThat(report.getNotes())
                .extracting(ImportReport.Note::message)
                .anyMatch(message -> message.contains("defaulted to 1521 for ORACLE"))
                .anyMatch(message -> message.contains("defaulted to 5236 for DAMENG"))
                .anyMatch(message -> message.contains("defaulted to 2881 for OCEANBASE"));
    }

    @Test
    void componentWithoutUsableBusinessDatabaseGetsExplicitNoProbePolicy() {
        LegacyEnvRow row = new LegacyEnvRow(102L, "环境 No DB",
                null, null, "https://env.example/health", "1.0", null, null,
                null, null, null, "oracle");

        importer.run(source(row), false);

        Component component = environments.findAll().get(0).getComponents().get(0);
        assertThat(component.getVersionProbe()).isEqualTo(VersionProbeKind.NONE);
    }

    @Test
    void keepsBusinessAndIntermediateRolesDistinctWhenTheyShareAConnection() {
        LegacyEnvRow row = new LegacyEnvRow(103L, "环境 Shared Roles",
                "app/pw@shared-db:1521/ORCL",
                "app/pw@shared-db:1521/ORCL",
                null, null, null, null, null, null, null, "oracle");

        importer.run(source(row), false);

        assertThat(databases.findAll())
                .extracting(Database::getRole)
                .containsExactlyInAnyOrder(Database.BUSINESS_ROLE, "intermediate");
        assertThat(environments.findAll().get(0).getComponents().get(0).getDatabaseIds()).hasSize(2);
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

        // The shared resources keep the first row's secret; the duplicate password is reported, not
        // stored over the top (ADR-0008).
        assertThat(broker.brokerServerCredential(sharedServerId).secret()).isEqualTo("pw");
        assertThat(broker.brokerDatabaseCredential(sharedDbId).secret()).isEqualTo("pw");
        assertThat(report.getNotes()).anySatisfy(n -> assertThat(n.message()).contains("not stored"));
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
        // A dry run sees the credential but persists no Server/Database, so nothing reaches the broker.
        assertThat(report.getCredentialsSeen()).isGreaterThan(0);
        assertThat(report.render()).contains("dry run; no secrets stored");
    }
}
