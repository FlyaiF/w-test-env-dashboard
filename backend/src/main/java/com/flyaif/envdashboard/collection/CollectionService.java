package com.flyaif.envdashboard.collection;

import com.flyaif.envdashboard.catalog.EnvironmentNotFoundException;
import com.flyaif.envdashboard.catalog.EnvironmentRepository;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.web.EnvironmentMapper;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.collection.probe.ProbeContext;
import com.flyaif.envdashboard.collection.probe.ProbeResult;
import com.flyaif.envdashboard.collection.probe.VersionProbe;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.Server;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * The Version Collection core capability. Refreshes each Component's live version, Version update time (版本更新时间), status,
 * and last-collected time by dispatching it to the {@link VersionProbe} for its kind. Each Component is
 * collected independently and defensively: a probe that throws or fails turns into a {@code FAILED}
 * status for that one Component, never blanking its siblings (PRD §6 graceful degradation).
 */
@Service
public class CollectionService {

    private static final Logger log = LoggerFactory.getLogger(CollectionService.class);

    private final EnvironmentRepository environments;
    private final ServerRepository servers;
    private final DatabaseRepository databases;
    private final VersionProbeRegistry probes;
    private final Clock clock;

    public CollectionService(EnvironmentRepository environments,
                             ServerRepository servers,
                             DatabaseRepository databases,
                             VersionProbeRegistry probes,
                             Clock clock) {
        this.environments = environments;
        this.servers = servers;
        this.databases = databases;
        this.probes = probes;
        this.clock = clock;
    }

    /** Manual "refresh now" for one Environment; returns its freshly-collected published view. */
    @Transactional
    public EnvironmentDto refresh(Long environmentId) {
        Environment environment = environments.findById(environmentId)
                .orElseThrow(() -> new EnvironmentNotFoundException(environmentId));
        environment.getComponents().forEach(this::collect);
        return EnvironmentMapper.toDto(environment);
    }

    /** Scheduled sweep across every Environment; returns the number of Components collected. */
    @Transactional
    public int refreshAll() {
        int collected = 0;
        for (Environment environment : environments.findAll()) {
            for (Component component : environment.getComponents()) {
                collect(component);
                collected++;
            }
        }
        return collected;
    }

    private void collect(Component component) {
        ProbeResult result;
        try {
            result = probes.forKind(component.getVersionProbe())
                    .map(probe -> probe.probe(context(component, probe)))
                    .orElseGet(() -> ProbeResult.unsupported(
                            "No version probe for kind " + component.getVersionProbe()));
        } catch (RuntimeException ex) {
            // A single probe failing must not abort the sweep or blank sibling Components.
            log.warn("Version probe failed for component {}: {}", component.getId(), ex.getMessage());
            result = ProbeResult.failed(ex.getMessage());
        }
        apply(component, result);
    }

    private void apply(Component component, ProbeResult result) {
        component.setCollectionStatus(result.status());
        component.setLastCollectedAt(clock.instant());
        // Only a successful probe overwrites the version; a failure leaves known-good data in place.
        switch (result.status()) {
            case OK -> {
                component.setVersion(result.version());
                if (result.versionUpdatedAt() != null) {
                    component.setVersionUpdatedAt(result.versionUpdatedAt());
                }
            }
            case FAILED, UNSUPPORTED -> { /* keep prior version/versionUpdatedAt */ }
        }
    }

    private ProbeContext context(Component component, VersionProbe probe) {
        Server server = component.getServerId() == null
                ? null
                : servers.findById(component.getServerId()).orElse(null);
        List<Database> used = new ArrayList<>();
        for (Long databaseId : component.getDatabaseIds()) {
            databases.findById(databaseId).ifPresent(used::add);
        }
        used.removeIf(Objects::isNull);
        return new ProbeContext(component, server, used);
    }
}
