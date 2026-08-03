package com.flyaif.envdashboard.collection;

import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.collection.probe.ProbeContext;
import com.flyaif.envdashboard.collection.probe.ProbeResult;
import com.flyaif.envdashboard.collection.probe.VersionProbe;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The registry is the heart of the pluggable extension point: it must route each kind to its probe,
 * treat an unhandled or {@code NONE}/null kind as "no probe", and refuse two probes for one kind.
 */
class VersionProbeRegistryTest {

    private static VersionProbe probeFor(VersionProbeKind kind) {
        return new VersionProbe() {
            @Override
            public VersionProbeKind kind() {
                return kind;
            }

            @Override
            public ProbeResult probe(ProbeContext context) {
                return ProbeResult.ok("v", null);
            }
        };
    }

    @Test
    void dispatchesEachKindToItsRegisteredProbe() {
        VersionProbe http = probeFor(VersionProbeKind.HTTP);
        VersionProbe db = probeFor(VersionProbeKind.DB);
        VersionProbeRegistry registry = new VersionProbeRegistry(List.of(http, db));

        assertThat(registry.forKind(VersionProbeKind.HTTP)).containsSame(http);
        assertThat(registry.forKind(VersionProbeKind.DB)).containsSame(db);
    }

    @Test
    void unhandledOrAbsentKindHasNoProbe() {
        VersionProbeRegistry registry = new VersionProbeRegistry(List.of(probeFor(VersionProbeKind.HTTP)));

        assertThat(registry.forKind(VersionProbeKind.COMMAND)).isEmpty(); // no probe registered
        assertThat(registry.forKind(VersionProbeKind.NONE)).isEmpty();
        assertThat(registry.forKind(null)).isEmpty();
    }

    @Test
    void refusesTwoProbesForTheSameKind() {
        assertThatThrownBy(() -> new VersionProbeRegistry(
                List.of(probeFor(VersionProbeKind.HTTP), probeFor(VersionProbeKind.HTTP))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("HTTP");
    }
}
