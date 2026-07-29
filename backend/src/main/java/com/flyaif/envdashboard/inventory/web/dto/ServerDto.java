package com.flyaif.envdashboard.inventory.web.dto;

/**
 * Published representation of a shared {@code Server} aggregate. {@code hasSecret} reports only
 * whether a brokered SSH secret is stored — never the secret itself (ADR-0005).
 */
public record ServerDto(
        Long id,
        String host,
        String os,
        SshAccessDto ssh,
        boolean hasSecret
) {
}
