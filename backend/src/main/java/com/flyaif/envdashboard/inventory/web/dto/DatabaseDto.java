package com.flyaif.envdashboard.inventory.web.dto;

/** Published representation of a shared {@code Database} aggregate. */
public record DatabaseDto(
        Long id,
        String role,
        String type,
        ConnectionDto connection
) {
}
