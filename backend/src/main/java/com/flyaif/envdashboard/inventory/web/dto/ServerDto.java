package com.flyaif.envdashboard.inventory.web.dto;

/** Published representation of a shared {@code Server} aggregate. */
public record ServerDto(
        Long id,
        String host,
        String os,
        SshAccessDto ssh
) {
}
