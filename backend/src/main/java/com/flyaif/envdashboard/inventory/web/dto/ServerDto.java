package com.flyaif.envdashboard.inventory.web.dto;

/**
 * Published representation of a shared {@code Server} aggregate. {@code hasSecret} reports only
 * whether a brokered SSH secret is stored — never the secret itself (ADR-0005).
 * {@code referenceCount} is how many Components run on this Server.
 */
public record ServerDto(
        Long id,
        String host,
        String os,
        SshAccessDto ssh,
        boolean hasSecret,
        long referenceCount
) {
}
