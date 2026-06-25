package com.flyaif.envdashboard.inventory;

/**
 * Port the Resource Inventory needs to guard deletions: is a shared resource still referenced by a
 * Component? The Catalog context owns Components and provides the adapter, so the dependency points
 * Catalog -> Inventory only (Inventory never imports Catalog).
 */
public interface ResourceUsage {

    boolean isServerInUse(Long serverId);

    boolean isDatabaseInUse(Long databaseId);
}
