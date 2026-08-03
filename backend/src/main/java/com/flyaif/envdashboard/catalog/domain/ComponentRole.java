package com.flyaif.envdashboard.catalog.domain;

/**
 * The role a {@link Component} plays within its Environment. Stored as a string so a
 * new or unexpected value stays legible rather than collapsing to an ordinal.
 *
 * <p>{@link #UNSPECIFIED} is the explicit "role not yet classified" value — the default for a
 * hand-added Component until a human classifies it (ADR-0007). The one-time TENVINFO migration
 * assigns {@link #APP}: the system owner confirmed every legacy entry is the main service.
 */
public enum ComponentRole {
    UNSPECIFIED,
    GATEWAY,
    UI,
    APP,
    PRIVATE_PROTO
}
