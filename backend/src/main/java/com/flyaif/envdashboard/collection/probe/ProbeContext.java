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

    /**
     * The Database the db-query probe targets: the linked Database with the well-known
     * {@link Database#BUSINESS_ROLE} (业务库 — where the upgrade process records version and
     * 版本更新时间), falling back to the first linked Database when no role matches.
     */
    public Optional<Database> businessDatabase() {
        return databases.stream()
                .filter(db -> Database.BUSINESS_ROLE.equalsIgnoreCase(db.getRole()))
                .findFirst()
                .or(() -> databases.stream().findFirst());
    }
}
