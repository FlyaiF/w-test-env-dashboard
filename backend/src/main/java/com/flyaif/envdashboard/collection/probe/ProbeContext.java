package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.Server;

import java.util.List;
import java.util.Optional;

/**
 * Everything a {@link VersionProbe} needs to reach a Component's running system: the Component itself
 * (URL, listen port, protocol) plus the shared Resource Inventory descriptors it is linked to — the
 * {@link Server} it runs on (or {@code null}) and the {@link Database}s it uses (0..N), resolved by ID
 * (ADR-0003). The collector builds this once per Component; probes read from it but never mutate it.
 */
public record ProbeContext(Component component, Server server, List<Database> databases) {

    /** The first linked Database, if any — the db-query probe targets it. */
    public Optional<Database> primaryDatabase() {
        return databases.isEmpty() ? Optional.empty() : Optional.of(databases.get(0));
    }
}
