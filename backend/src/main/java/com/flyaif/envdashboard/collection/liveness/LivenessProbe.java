package com.flyaif.envdashboard.collection.liveness;

/**
 * Checks whether one URL is serving. Implementations must be bounded in time and must not throw:
 * every failure is classified into a {@link LivenessCheck}.
 */
public interface LivenessProbe {

    LivenessCheck check(String url);
}
