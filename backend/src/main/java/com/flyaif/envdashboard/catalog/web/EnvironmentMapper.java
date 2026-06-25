package com.flyaif.envdashboard.catalog.web;

import com.flyaif.envdashboard.catalog.domain.CollectionStatus;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;

import java.util.List;

/**
 * Maps the {@link Environment} aggregate to its published DTO contract. Enums serialize as their
 * names so the wire stays legible; the client owns the reverse interpretation (slice 02).
 */
public final class EnvironmentMapper {

    private EnvironmentMapper() {
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
