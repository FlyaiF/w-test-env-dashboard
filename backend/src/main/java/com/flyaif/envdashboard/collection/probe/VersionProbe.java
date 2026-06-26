package com.flyaif.envdashboard.collection.probe;

import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;

/**
 * The pluggable, named extension point of the Version Collection capability: one strategy for obtaining
 * a Component's live version. Each implementation declares the {@link VersionProbeKind} it handles and
 * is discovered as a Spring bean, so a new Component type adds a probe by implementing this interface
 * and nothing else — existing probes are never edited (open/closed).
 *
 * <p>Probes are pure with respect to the rest of the system: they reach the outside world only through
 * the shared Machine Access capability handed to them, which keeps them deterministic under test.
 */
public interface VersionProbe {

    /** The Component kind this probe handles; the registry dispatches on it. */
    VersionProbeKind kind();

    /** Obtain the live version for the given Component context. Must not throw for an expected
     *  failure (unreachable host, missing config) — return {@link ProbeResult#failed} instead, so one
     *  Component degrades without affecting its siblings. */
    ProbeResult probe(ProbeContext context);
}
