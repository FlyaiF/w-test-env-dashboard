package com.flyaif.envdashboard.clientupdate.web.dto;

import com.flyaif.envdashboard.clientupdate.ClientRelease;

/**
 * The published description of the newest env_viewer build for one platform. {@code sha256} lets
 * the client verify the download before handing it to the updater helper; {@code notes} is the
 * optional operator-written release-notes markdown shown in the update popup.
 */
public record ClientUpdateDto(
        String version,
        String platform,
        String fileName,
        long sizeBytes,
        String sha256,
        String notes
) {

    public static ClientUpdateDto from(ClientRelease release) {
        return new ClientUpdateDto(
                release.version(),
                release.platform(),
                release.zip().getFileName().toString(),
                release.sizeBytes(),
                release.sha256(),
                release.notes());
    }
}
