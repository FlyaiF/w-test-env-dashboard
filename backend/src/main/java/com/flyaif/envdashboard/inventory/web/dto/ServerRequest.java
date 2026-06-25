package com.flyaif.envdashboard.inventory.web.dto;

import com.flyaif.envdashboard.inventory.domain.ServerOs;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/** Create/update payload for a {@code Server}. */
public record ServerRequest(
        @NotBlank String host,
        @NotNull ServerOs os,
        SshAccessDto ssh
) {
}
