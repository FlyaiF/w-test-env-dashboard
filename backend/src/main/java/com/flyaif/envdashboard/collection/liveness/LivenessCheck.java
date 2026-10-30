package com.flyaif.envdashboard.collection.liveness;

import com.flyaif.envdashboard.catalog.domain.LivenessStatus;

/**
 * Outcome of one liveness check against a Component's URL: the {@link LivenessStatus} and a short
 * operator-facing {@code detail} (e.g. {@code HTTP 302}, {@code connection refused}).
 */
public record LivenessCheck(LivenessStatus status, String detail) {

    public static LivenessCheck up(String detail) {
        return new LivenessCheck(LivenessStatus.UP, detail);
    }

    public static LivenessCheck down(String detail) {
        return new LivenessCheck(LivenessStatus.DOWN, detail);
    }

    public static LivenessCheck unreachable(String detail) {
        return new LivenessCheck(LivenessStatus.UNREACHABLE, detail);
    }
}
