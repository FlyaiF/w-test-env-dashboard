package com.flyaif.envdashboard.catalog.web;

import com.flyaif.envdashboard.catalog.domain.CollectionStatus;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.ComponentRequest;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;

import java.util.List;

/**
 * Maps the {@link Environment} aggregate to its published DTO contract. Enums serialize as their
 * names so the wire stays legible; the client owns the reverse interpretation (slice 02). The
 * write path (slice 03) reuses {@link #toDomain} / {@link #applyTo} to turn a request into Component
 * state — limited to the curated descriptive fields, never the links or collected status.
 */
public final class EnvironmentMapper {

    private EnvironmentMapper() {
    }

    /** Build a new {@link Component} from a create request. */
    public static Component toDomain(ComponentRequest request) {
        Component component = new Component(request.role());
        applyTo(component, request);
        return component;
    }

    /**
     * Copy a request's curated fields onto an existing {@link Component}. Deliberately leaves
     * {@code serverId}/{@code databaseIds} (links, slice 04) and the Collection fields (slice 05)
     * alone, so editing a Component never silently drops its links or last collected version.
     */
    public static void applyTo(Component component, ComponentRequest request) {
        component.setRole(request.role());
        component.setVersion(request.version());
        component.setDeployTime(request.deployTime());
        component.setLogLocation(request.logLocation());
        component.setListenPort(request.listenPort());
        component.setProtocol(request.protocol());
        component.setUrl(request.url());
        component.setVersionProbe(request.versionProbe());
    }

    public static EnvironmentDto toDto(Environment environment) {
        List<ComponentDto> components = environment.getComponents().stream()
                .map(EnvironmentMapper::toDto)
                .toList();
        return new EnvironmentDto(
                environment.getId(),
                environment.getName(),
                environment.getMemo(),
                components);
    }

    public static ComponentDto toDto(Component component) {
        return new ComponentDto(
                component.getId(),
                name(component.getRole()),
                component.getVersion(),
                component.getDeployTime(),
                component.getLogLocation(),
                component.getListenPort(),
                component.getProtocol(),
                component.getUrl(),
                component.getServerId(),
                List.copyOf(component.getDatabaseIds()),
                name(component.getVersionProbe()),
                name(component.getCollectionStatus()),
                component.getLastCollectedAt());
    }

    private static String name(ComponentRole role) {
        return role == null ? null : role.name();
    }

    private static String name(VersionProbeKind probe) {
        return probe == null ? null : probe.name();
    }

    private static String name(CollectionStatus status) {
        return status == null ? null : status.name();
    }
}
