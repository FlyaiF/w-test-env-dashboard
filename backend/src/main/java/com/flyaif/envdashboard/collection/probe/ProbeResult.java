package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.CollectionStatus;

import java.time.Instant;

/**
 * Outcome of running a {@link VersionProbe} against one Component. Carries the probe's
 * {@link CollectionStatus}, the live {@code version} it found (and its {@code versionUpdatedAt}, if the
 * probe can tell), and a free-text {@code detail} that explains a non-OK result for the operator.
 *
 * <p>Only an {@link CollectionStatus#OK} result carries a version; {@code FAILED}/{@code UNSUPPORTED}
 * leave the Component's existing version untouched so a flaky probe never blanks known-good data.
 */
public record ProbeResult(CollectionStatus status, String version, Instant versionUpdatedAt, String detail) {

    public static ProbeResult ok(String version, Instant versionUpdatedAt) {
        return new ProbeResult(CollectionStatus.OK, version, versionUpdatedAt, null);
    }

    public static ProbeResult failed(String detail) {
        return new ProbeResult(CollectionStatus.FAILED, null, null, detail);
    }

    public static ProbeResult unsupported(String detail) {
        return new ProbeResult(CollectionStatus.UNSUPPORTED, null, null, detail);
    }
}
