package com.flyaif.envdashboard.inventory.web.dto;

/** Non-secret database connection metadata on the wire (no password — brokered in slice 06). */
public record ConnectionDto(
        String host,
        Integer port,
        String serviceName,
        String username
) {
}
