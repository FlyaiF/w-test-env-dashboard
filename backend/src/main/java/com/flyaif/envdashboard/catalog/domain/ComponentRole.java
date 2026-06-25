package com.flyaif.envdashboard.catalog.domain;

/**
 * The role a {@link Component} plays within its Environment. Stored as a string so a
 * new or unexpected value stays legible rather than collapsing to an ordinal.
 */
public enum ComponentRole {
    GATEWAY,
    UI,
    APP,
    PRIVATE_PROTO
}
