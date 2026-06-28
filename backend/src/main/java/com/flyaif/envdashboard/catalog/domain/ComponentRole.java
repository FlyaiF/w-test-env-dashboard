package com.flyaif.envdashboard.catalog.domain;

/**
 * The role a {@link Component} plays within its Environment. Stored as a string so a
 * new or unexpected value stays legible rather than collapsing to an ordinal.
 *
 * <p>{@link #UNSPECIFIED} is the explicit "role not yet classified" value — used by the
 * one-time TENVINFO migration, whose flat rows carry no role discriminator, so it records
 * the absence honestly instead of guessing a real role (ADR-0007). A human classifies it later.
 */
public enum ComponentRole {
    UNSPECIFIED,
    GATEWAY,
    UI,
    APP,
    PRIVATE_PROTO
}
