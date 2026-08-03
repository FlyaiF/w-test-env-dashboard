package com.flyaif.envdashboard.catalog.domain;

/**
 * The pluggable strategy used to obtain a {@link Component}'s live Version. Null until
 * the collector lands (slice 05); the value picked depends on the Component/Server.
 */
public enum VersionProbeKind {
    DB,
    SSH_FILE,
    COMMAND,
    HTTP,
    NONE
}
