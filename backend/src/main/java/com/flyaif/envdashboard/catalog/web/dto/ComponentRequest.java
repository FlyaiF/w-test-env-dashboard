package com.flyaif.envdashboard.catalog.web.dto;

import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import jakarta.validation.constraints.NotNull;

import java.time.Instant;

/**
 * Create/update payload for a curated Component. Carries only the human-curated descriptive fields:
 * the runs-on Server / uses Databases links have their own endpoint ({@code PUT /api/components/{id}/links},
 * slice 04) and the Collection bookkeeping ({@code collectionStatus}, {@code lastCollectedAt}) is owned
 * by the collector (slice 05) — neither is settable here, so curation never clobbers collected state.
 */
public record ComponentRequest(
        @NotNull ComponentRole role,
        String version,
        Instant deployTime,
        String logLocation,
        Integer listenPort,
        String protocol,
        String url,
        VersionProbeKind versionProbe
) {
}
