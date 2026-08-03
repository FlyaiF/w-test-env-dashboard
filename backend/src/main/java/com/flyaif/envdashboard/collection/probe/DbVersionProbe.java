package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
import com.flyaif.envdashboard.inventory.domain.Database;
import org.springframework.stereotype.Component;

import java.time.Instant;

/**
 * Obtains a Component's version and 版本更新时间 from its business Database (业务库), the way the legacy
 * dashboard did: the upgrade process records the system version in {@code tsys_parameter} and appends a
 * row to {@code jres_subsystem_rc} each time a schema change runs — that row's {@code begin_time} is
 * the Version update time. Targets the linked Database via {@link ProbeContext#businessDatabase()};
 * registered for {@link VersionProbeKind#DB}.
 *
 * <p>Strictness (issue 08): a connection/SQL error or a missing/blank SystemVersion parameter fails the
 * probe (prior known-good values stay in place); an empty {@code jres_subsystem_rc} — append-only, so
 * "empty" means no schema change has ever run — still succeeds, with a version but no 版本更新时间.
 */
@Component
public class DbVersionProbe implements VersionProbe {

    /** The system version the upgrade process maintains in the business DB. */
    static final String VERSION_QUERY =
            "select param_value from tsys_parameter where param_code = 'SystemVersion'";

    /** The latest schema-change run; its begin_time is the 版本更新时间. */
    static final String VERSION_UPDATED_AT_QUERY =
            "select * from (select begin_time from jres_subsystem_rc order by begin_time desc)"
                    + " where rownum = 1";

    private final MachineAccess machineAccess;

    public DbVersionProbe(MachineAccess machineAccess) {
        this.machineAccess = machineAccess;
    }

    @Override
    public VersionProbeKind kind() {
        return VersionProbeKind.DB;
    }

    @Override
    public ProbeResult probe(ProbeContext context) {
        Database database = context.businessDatabase().orElse(null);
        if (database == null) {
            return ProbeResult.failed(
                    "DB probe needs a linked business Database (role \"" + Database.BUSINESS_ROLE
                            + "\"), but the Component uses none");
        }
        String version = machineAccess.queryScalar(database, VERSION_QUERY);
        if (version == null || version.isBlank()) {
            return ProbeResult.failed(
                    "business database " + database.getId() + " has no SystemVersion parameter");
        }
        Instant versionUpdatedAt = machineAccess.queryInstant(database, VERSION_UPDATED_AT_QUERY);
        return ProbeResult.ok(version.strip(), versionUpdatedAt);
    }
}
