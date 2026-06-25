package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.inventory.ResourceUsage;
import org.springframework.transaction.annotation.Transactional;

/**
 * Catalog's adapter for the Inventory {@link ResourceUsage} port: answers whether any Component
 * references a shared Server/Database, so Inventory can refuse to delete one that is still in use
 * (ADR-0003) without importing the Catalog context.
 */
@org.springframework.stereotype.Component
@Transactional(readOnly = true)
public class CatalogResourceUsage implements ResourceUsage {

    private final EnvironmentRepository environments;

    public CatalogResourceUsage(EnvironmentRepository environments) {
        this.environments = environments;
    }

    @Override
    public boolean isServerInUse(Long serverId) {
        return environments.existsByComponentsServerId(serverId);
    }

    @Override
    public boolean isDatabaseInUse(Long databaseId) {
        return environments.existsByDatabaseId(databaseId);
    }
}
