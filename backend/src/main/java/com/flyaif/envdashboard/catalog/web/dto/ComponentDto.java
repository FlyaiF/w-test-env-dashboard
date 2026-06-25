package com.flyaif.envdashboard.catalog.web.dto;

import java.time.Instant;

/**
 * The server's published representation of a Component. Field names follow the glossary
 * ({@code version}, {@code deployTime}) — no legacy {@code e_*}/{@code webserver} terms.
 * Collection fields are present but null until slice 05.
 */
public record ComponentDto(
        Long id,
        String role,
        String version,
        Instant deployTime,
        String logLocation,
        Integer listenPort,
        String protocol,
        String url,
        String versionProbe,
        String collectionStatus,
        Instant lastCollectedAt
) {
}
