package com.flyaif.envdashboard.inventory.web.dto;

import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import jakarta.validation.constraints.NotNull;

/** Create/update payload for a {@code Database}. */
public record DatabaseRequest(
        String role,
        @NotNull DatabaseType type,
        ConnectionDto connection
) {
}
