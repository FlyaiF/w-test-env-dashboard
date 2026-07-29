package com.flyaif.envdashboard.inventory.web.dto;

/**
 * Published representation of a shared {@code Database} aggregate. {@code hasSecret} reports only
 * whether a brokered login secret is stored — never the secret itself (ADR-0005).
 */
public record DatabaseDto(
        Long id,
        String role,
        String type,
        ConnectionDto connection,
        boolean hasSecret
) {
}
