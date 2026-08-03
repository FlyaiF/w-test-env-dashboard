package com.flyaif.envdashboard.inventory.domain;

/** Engine of a {@link Database}. Stored as a string so a new engine stays legible, not an ordinal. */
public enum DatabaseType {
    ORACLE,
    DAMENG,
    OCEANBASE,
    OTHER
}
