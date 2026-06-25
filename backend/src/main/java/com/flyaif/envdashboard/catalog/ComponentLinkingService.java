package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.web.EnvironmentMapper;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.inventory.DatabaseNotFoundException;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerNotFoundException;
import com.flyaif.envdashboard.inventory.ServerRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Links a {@link Component} to the Resource Inventory: the Server it runs on and the Databases it
 * uses, both by ID (ADR-0003). Referenced resources are validated to exist before the link is set,
 * so a Component can never point at a non-existent Server/Database.
 */
@Service
@Transactional
public class ComponentLinkingService {

    private final ComponentRepository components;
    private final ServerRepository servers;
    private final DatabaseRepository databases;

    public ComponentLinkingService(ComponentRepository components,
                                   ServerRepository servers,
                                   DatabaseRepository databases) {
        this.components = components;
        this.servers = servers;
        this.databases = databases;
    }

    public ComponentDto setLinks(Long componentId, Long serverId, Set<Long> databaseIds) {
        Component component = components.findById(componentId)
                .orElseThrow(() -> new ComponentNotFoundException(componentId));

        Set<Long> uses = databaseIds == null ? Set.of() : new LinkedHashSet<>(databaseIds);

        if (serverId != null && !servers.existsById(serverId)) {
            throw new ServerNotFoundException(serverId);
        }
        for (Long databaseId : uses) {
            if (!databases.existsById(databaseId)) {
                throw new DatabaseNotFoundException(databaseId);
            }
        }

        component.setServerId(serverId);
        component.setDatabaseIds(uses);
        return EnvironmentMapper.toDto(component);
    }
}
