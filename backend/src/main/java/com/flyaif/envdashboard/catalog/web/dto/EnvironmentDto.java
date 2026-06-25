package com.flyaif.envdashboard.catalog.web.dto;

import java.util.List;

/**
 * The server's published representation of an Environment aggregate, with its owned Components.
 * This is the contract the thin client builds its anti-corruption layer over (slice 02).
 */
public record EnvironmentDto(
        Long id,
        String name,
        String memo,
        List<ComponentDto> components
) {
}
