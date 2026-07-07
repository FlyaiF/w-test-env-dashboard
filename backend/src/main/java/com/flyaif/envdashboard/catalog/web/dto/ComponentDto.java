package com.flyaif.envdashboard.catalog.web.dto;

import java.time.Instant;
import java.util.List;

/**
 * The server's published representation of a Component. Field names follow the glossary
 * ({@code version}, {@code versionUpdatedAt}) — no legacy {@code e_*}/{@code webserver} terms.
 * {@code serverId} (runs-on) and {@code databaseIds} (uses) are references by ID into the Resource
 * Inventory (ADR-0003). Collection fields are present but null until slice 05.
 */
public record ComponentDto(
        Long id,
        String role,
        String version,
        Instant versionUpdatedAt,
        String logLocation,
        Integer listenPort,
        String protocol,
        String url,
        Long serverId,
        List<Long> databaseIds,
        String versionProbe,
        String collectionStatus,
        Instant lastCollectedAt
) {
}
