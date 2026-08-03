package com.flyaif.envdashboard.collection;

import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.collection.probe.VersionProbe;
import org.springframework.stereotype.Component;

import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Discovers every {@link VersionProbe} bean and indexes it by the {@link VersionProbeKind} it handles,
 * so the collector can dispatch a Component to its probe without a switch. This is what makes the
 * extension point pluggable: a new probe bean appears here automatically, and no existing code changes.
 */
@Component
public class VersionProbeRegistry {

    private final Map<VersionProbeKind, VersionProbe> byKind;

    public VersionProbeRegistry(List<VersionProbe> probes) {
        Map<VersionProbeKind, VersionProbe> map = new EnumMap<>(VersionProbeKind.class);
        for (VersionProbe probe : probes) {
            VersionProbe previous = map.put(probe.kind(), probe);
            if (previous != null) {
                throw new IllegalStateException(
                        "Two probes registered for kind " + probe.kind() + ": "
                                + previous.getClass().getName() + " and " + probe.getClass().getName());
            }
        }
        this.byKind = map;
    }

    /** The probe for this kind, or empty if the kind is null/NONE or has no registered probe. */
    public Optional<VersionProbe> forKind(VersionProbeKind kind) {
        return kind == null ? Optional.empty() : Optional.ofNullable(byKind.get(kind));
    }
}
