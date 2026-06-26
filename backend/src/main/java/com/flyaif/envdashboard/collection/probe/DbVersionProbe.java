package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.collection.machine.MachineAccess;
import com.flyaif.envdashboard.inventory.domain.Database;
import org.springframework.stereotype.Component;

/**
 * Obtains a Component's version by querying one of the Databases it uses (slice-04 descriptor) through
 * the shared Machine Access capability. Targets the Component's primary Database and reads a single
 * scalar version value. Registered for {@link VersionProbeKind#DB}.
 */
@Component
public class DbVersionProbe implements VersionProbe {

    /** Conventional one-row version lookup; deployments standardise on this view/table. */
    static final String VERSION_QUERY = "SELECT version FROM app_version WHERE ROWNUM = 1";

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
        Database database = context.primaryDatabase().orElse(null);
        if (database == null) {
            return ProbeResult.failed("DB probe needs a linked Database, but the Component uses none");
        }
        String version = machineAccess.queryScalar(database, VERSION_QUERY);
        if (version == null || version.isBlank()) {
            return ProbeResult.failed("DB probe got an empty version from database " + database.getId());
        }
        return ProbeResult.ok(version.strip(), null);
    }
}
