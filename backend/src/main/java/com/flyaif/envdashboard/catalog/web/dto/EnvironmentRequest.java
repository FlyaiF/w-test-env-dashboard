package com.flyaif.envdashboard.catalog.web.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

/**
 * Create/update payload for an Environment. On create, {@code components} may carry inline Components
 * to seed the aggregate; on update it is ignored — Components are edited through the nested
 * {@code /api/environments/{id}/components} endpoints so each change is an explicit, scoped operation.
 */
public record EnvironmentRequest(
        @NotBlank String name,
        String memo,
        @Valid List<ComponentRequest> components
) {
}
