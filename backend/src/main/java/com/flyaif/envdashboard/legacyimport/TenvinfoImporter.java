package com.flyaif.envdashboard.legacyimport;

import com.flyaif.envdashboard.access.AccessBrokerService;
import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.JdbcUrlBuilder;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.ServerOs;
import com.flyaif.envdashboard.inventory.domain.SshAccess;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * The one-time {@code TENVINFO} → new-schema import (ADR-0004, PRD §8). Reads legacy rows from a
 * {@link LegacyEnvSource}, parses the composite strings and fixed DB slots into proper aggregates, and
 * writes Environment / Component / Server / Database rows — deduplicating shared Servers and Databases
 * so one machine/DB referenced by several rows becomes a single shared aggregate (ADR-0003).
 *
 * <p>Policy for messy data (PRD §8): a dirty-but-usable field is left blank and reported; a row that
 * cannot fit the new shape (no name) is dropped and reported. Nothing is silently discarded.
 *
 * <p>{@code dryRun} runs the full parse-and-plan and produces an identical {@link ImportReport} but
 * persists nothing — the migration's preview mode.
 */
@Service
public class TenvinfoImporter {

    /** Slot label for the legacy business DB (业务库) — the probe-targeted role (issue 08). */
    private static final String BUSINESS_DB_ROLE = Database.BUSINESS_ROLE;
    /** Slot label for the legacy intermediate DB (中间库). */
    private static final String INTERMEDIATE_DB_ROLE = "intermediate";

    private final EnvironmentRepository environments;
    private final ServerRepository servers;
    private final DatabaseRepository databases;
    private final AccessBrokerService broker;

    public TenvinfoImporter(EnvironmentRepository environments,
                            ServerRepository servers,
                            DatabaseRepository databases,
                            AccessBrokerService broker) {
        this.environments = environments;
        this.servers = servers;
        this.databases = databases;
        this.broker = broker;
    }

    @Transactional
    public ImportReport run(LegacyEnvSource source, boolean dryRun) {
        // Safe re-runnability (PRD §8): the one-time import targets a fresh schema. Refuse to write
        // into a non-empty one so a re-run can never silently duplicate rows. Dry runs always proceed.
        if (!dryRun) {
            long existing = environments.count() + servers.count() + databases.count();
            if (existing > 0) {
                throw new IllegalStateException(
                        "Target schema is not empty (" + existing + " catalog/inventory row(s) present). "
                                + "The one-time TENVINFO import expects a fresh schema; clear it before "
                                + "re-running to avoid duplicates, or use dry-run to preview.");
            }
        }

        ImportReport report = new ImportReport(dryRun);
        // Within one run, the same host / database is one shared aggregate (ADR-0003).
        Map<String, Server> serverByKey = new LinkedHashMap<>();
        Map<String, Database> databaseByKey = new LinkedHashMap<>();

        for (LegacyEnvRow row : source.readAll()) {
            importRow(row, dryRun, report, serverByKey, databaseByKey);
        }
        return report;
    }

    private void importRow(LegacyEnvRow row, boolean dryRun, ImportReport report,
                           Map<String, Server> serverByKey, Map<String, Database> databaseByKey) {
        String name = blankToNull(row.name());
        if (name == null) {
            report.droppedRow(row.eNo(), "E_NAME is blank; an Environment must have a name");
            return;
        }

        Environment environment = new Environment(name, blankToNull(row.memo()));
        // E_SEEURL is the environment's console in SEE (公司环境管理平台) — an environment-level
        // fact, mapped 1:1; it never doubles as a component reachability url.
        environment.setSeeUrl(blankToNull(row.seeUrl()));
        Component component = buildComponent(row, dryRun, report, serverByKey, databaseByKey);
        if (component != null) {
            environment.addComponent(component);
            report.componentCreated();
        } else {
            report.note(row.eNo(), "no component-level data; imported as an Environment with no Components");
        }

        if (!dryRun) {
            environments.save(environment);
        }
        report.importedEnvironment(row.eNo());
    }

    /** Build the single Component the legacy row describes (its web server), or null if it has none. */
    private Component buildComponent(LegacyEnvRow row, boolean dryRun, ImportReport report,
                                     Map<String, Server> serverByKey, Map<String, Database> databaseByKey) {
        Server server = resolveServer(row, dryRun, report, serverByKey);
        String url = blankToNull(row.url());
        String version = blankToNull(row.version());
        String logLocation = blankToNull(row.webLogPath());

        DatabaseType dbType = LegacyDbTypeMapper.map(row.dbType());
        Database businessDb = resolveDatabase(
                row.businessDb(), BUSINESS_DB_ROLE, dbType, "E_YWDB", row.eNo(), dryRun, report, databaseByKey);
        Database intermediateDb = resolveDatabase(
                row.intermediateDb(), INTERMEDIATE_DB_ROLE, dbType, "E_ZJDB", row.eNo(), dryRun, report, databaseByKey);

        boolean hasData = server != null || url != null || version != null || logLocation != null
                || row.updateTime() != null || businessDb != null || intermediateDb != null;
        if (!hasData) {
            return null;
        }

        // Every legacy TENVINFO "web server" entry is the environment's main service, per the
        // system owner (ADR-0007, superseded note) — so APP is recorded fact, not a guess.
        Component component = new Component(ComponentRole.APP);
        component.setVersion(version);
        component.setVersionUpdatedAt(row.updateTime());
        component.setLogLocation(logLocation);
        component.setUrl(url);
        // The legacy dashboard reads the live version from E_YWDB. Preserve that behavior explicitly
        // on cutover; otherwise Collection sees a null probe kind and marks every migrated component
        // UNSUPPORTED. With no usable business DB, NONE records the deliberate no-probe policy rather
        // than leaving an ambiguous null for an operator to diagnose later.
        component.setVersionProbe(businessDb == null ? VersionProbeKind.NONE : VersionProbeKind.DB);
        if (server != null) {
            component.setServerId(server.getId());
        }
        component.setDatabaseIds(databaseIds(businessDb, intermediateDb));
        return component;
    }

    private Set<Long> databaseIds(Database businessDb, Database intermediateDb) {
        Set<Long> ids = new LinkedHashSet<>();
        if (businessDb != null && businessDb.getId() != null) {
            ids.add(businessDb.getId());
        }
        if (intermediateDb != null && intermediateDb.getId() != null) {
            ids.add(intermediateDb.getId());
        }
        return ids;
    }

    private Server resolveServer(LegacyEnvRow row, boolean dryRun, ImportReport report,
                                 Map<String, Server> serverByKey) {
        String raw = blankToNull(row.webServerAddr());
        if (raw == null) {
            return null;
        }
        Optional<WebServerAddr> parsed = WebServerAddrParser.parse(raw);
        if (parsed.isEmpty()) {
            report.blankedField(row.eNo(), "E_WEBSERVERADDR",
                    "could not parse a host from \"" + LegacyValueRedactor.redact(raw) + "\"");
            return null;
        }
        WebServerAddr addr = parsed.get();
        if (addr.password() != null || addr.username() != null) {
            report.credentialSeen();
        }

        String key = addr.host().toLowerCase(Locale.ROOT);
        Server existing = serverByKey.get(key);
        if (existing != null) {
            report.serverReused();
            if (addr.password() != null) {
                report.note(row.eNo(), "server " + addr.host()
                        + ": a second SSH password was seen but not stored (the shared server already has one)");
            }
            return existing;
        }
        Server server = new Server(addr.host(), ServerOs.LINUX,
                new SshAccess(addr.host(), addr.port(), addr.username()));
        report.serverCreated();
        report.note(row.eNo(), "server " + addr.host() + ": OS defaulted to LINUX (legacy had none)");
        if (!dryRun) {
            server = servers.save(server);
            if (addr.password() != null) {
                // Migrate the legacy plaintext SSH secret into the encrypted broker (ADR-0008); it is
                // never returned on the Server's Inventory DTO, only via on-demand brokering.
                broker.storeServerSecret(server.getId(), addr.password());
            }
        }
        serverByKey.put(key, server);
        return server;
    }

    private Database resolveDatabase(String raw, String role, DatabaseType type, String field, long eNo,
                                     boolean dryRun, ImportReport report, Map<String, Database> databaseByKey) {
        String value = blankToNull(raw);
        if (value == null) {
            return null;
        }
        Optional<LegacyDbRef> parsed = LegacyDbSlotParser.parse(value);
        if (parsed.isEmpty()) {
            report.blankedField(eNo, field,
                    "could not parse a host from \"" + LegacyValueRedactor.redact(value) + "\"");
            return null;
        }
        LegacyDbRef ref = parsed.get();
        if (ref.password() != null) {
            report.credentialSeen();
        }
        Integer port = ref.port();
        if (port == null) {
            port = JdbcUrlBuilder.defaultPort(type);
            if (port != null) {
                report.note(eNo, field + " " + ref.host() + ": port omitted; defaulted to "
                        + port + " for " + type.name());
            } else {
                report.note(eNo, field + " " + ref.host()
                        + ": port omitted and left blank; database type has no deterministic default");
            }
        }

        // Role is load-bearing for DB version Collection: ProbeContext selects the linked database
        // whose role is "business". The same endpoint appearing in E_ZJDB and E_YWDB must therefore
        // remain two role-specific inventory records instead of whichever role happened to be seen
        // first winning during deduplication.
        String key = String.join("|", role, type.name(),
                ref.host().toLowerCase(Locale.ROOT),
                String.valueOf(port),
                String.valueOf(ref.serviceName()),
                String.valueOf(ref.username()));
        Database existing = databaseByKey.get(key);
        if (existing != null) {
            report.databaseReused();
            if (ref.password() != null) {
                report.note(eNo, field + " " + ref.host()
                        + ": a second DB password was seen but not stored (the shared database already has one)");
            }
            return existing;
        }
        Database database = new Database(role, type,
                new ConnectionDescriptor(ref.host(), port, ref.serviceName(), ref.username()));
        report.databaseCreated();
        if (!dryRun) {
            database = databases.save(database);
            if (ref.password() != null) {
                // Migrate the legacy plaintext DB secret into the encrypted broker (ADR-0008); it is
                // never returned on the Database's Inventory DTO, only via on-demand brokering.
                broker.storeDatabaseSecret(database.getId(), ref.password());
            }
        }
        databaseByKey.put(key, database);
        return database;
    }

    private static String blankToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
