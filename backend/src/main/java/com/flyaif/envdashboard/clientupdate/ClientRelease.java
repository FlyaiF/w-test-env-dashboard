package com.flyaif.envdashboard.clientupdate;

import java.nio.file.Path;

/**
 * One publishable client build found in the updates directory: a
 * {@code env_viewer-<version>-<platform>.zip} plus its optional sidecar release notes.
 */
public record ClientRelease(
        String version,
        String platform,
        Path zip,
        long sizeBytes,
        String sha256,
        String notes) {}
