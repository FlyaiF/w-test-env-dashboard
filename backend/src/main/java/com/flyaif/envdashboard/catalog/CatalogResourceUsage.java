package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.inventory.ResourceUsage;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Catalog's adapter for the Inventory {@link ResourceUsage} port: answers whether any Component
 * references a shared Server/Database, so Inventory can refuse to delete one that is still in use
 * (ADR-0003) without importing the Catalog context. Also serves the per-resource reference counts
 * shown as the 引用 column in the Resource Inventory tables.
 */
@org.springframework.stereotype.Component
@Transactional(readOnly = true)
public class CatalogResourceUsage implements ResourceUsage {

    private final EnvironmentRepository environments;
    private final ComponentRepository components;

    public CatalogResourceUsage(EnvironmentRepository environments, ComponentRepository components) {
        this.environments = environments;
        this.components = components;
    }

    @Override
    public boolean isServerInUse(Long serverId) {
        return environments.existsByComponentsServerId(serverId);
    }

    @Override
    public boolean isDatabaseInUse(Long databaseId) {
        return environments.existsByDatabaseId(databaseId);
    }

    @Override
    public Map<Long, Long> serverReferenceCounts() {
        return toCountMap(components.countGroupedByServer());
    }

    @Override
    public Map<Long, Long> databaseReferenceCounts() {
        return toCountMap(components.countGroupedByDatabase());
    }

    private static Map<Long, Long> toCountMap(List<Object[]> rows) {
        Map<Long, Long> counts = new HashMap<>();
        for (Object[] row : rows) {
            counts.put(((Number) row[0]).longValue(), ((Number) row[1]).longValue());
        }
        return counts;
    }
}
