package com.flyaif.envdashboard.catalog.domain;

/**
 * Outcome of the most recent Collection for a {@link Component}. Null until the
 * collector lands (slice 05); a per-component status lets one failed probe degrade
 * gracefully instead of blanking the whole Environment.
 */
public enum CollectionStatus {
    OK,
    FAILED,
    UNSUPPORTED
}
