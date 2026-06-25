package com.flyaif.envdashboard.inventory.web.dto;

/** Non-secret SSH access descriptor on the wire (no password/key — brokered in slice 06). */
public record SshAccessDto(
        String host,
        Integer port,
        String username
) {
}
