package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.web.EnvironmentMapper;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.ComponentRequest;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * Read and curation use-cases for the Environment Catalog. Mapping to the published DTO happens
 * here, inside the transaction, so lazily-loaded parts of the aggregate (Components and their
 * Database links) resolve without leaking persistence concerns into the web layer.
 *
 * <p>The class default is a read-only transaction; the write methods opt back in with their own
 * {@code @Transactional}. Components are only ever reached through their owning Environment (the
 * aggregate root), so deleting an Environment cascades to its Components and never touches a shared
 * Server/Database (ADR-0003).
 */
@Service
@Transactional(readOnly = true)
public class EnvironmentService {

    private final EnvironmentRepository repository;

    public EnvironmentService(EnvironmentRepository repository) {
        this.repository = repository;
    }

    public List<EnvironmentDto> listEnvironments() {
        return repository.findAll().stream()
                .map(EnvironmentMapper::toDto)
                .toList();
    }

    public EnvironmentDto getEnvironment(Long id) {
        return repository.findById(id)
                .map(EnvironmentMapper::toDto)
                .orElseThrow(() -> new EnvironmentNotFoundException(id));
    }

    /** Reverse lookup (ADR-0003): which Environments have a Component running on this Server? */
    public List<EnvironmentDto> environmentsOnServer(Long serverId) {
        return repository.findDistinctByComponentsServerId(serverId).stream()
                .map(EnvironmentMapper::toDto)
                .toList();
    }

    /** Reverse lookup (ADR-0003): which Environments have a Component using this Database? */
    public List<EnvironmentDto> environmentsUsingDatabase(Long databaseId) {
        return repository.findDistinctByDatabaseId(databaseId).stream()
                .map(EnvironmentMapper::toDto)
                .toList();
    }

    /** Create an Environment, seeding any inline Components carried on the request. */
    @Transactional
    public EnvironmentDto createEnvironment(EnvironmentRequest request) {
        Environment environment = new Environment(request.name(), request.memo());
        environment.setSeeUrl(normalizeSeeUrl(request.seeUrl()));
        if (request.components() != null) {
            request.components().forEach(c -> environment.addComponent(EnvironmentMapper.toDomain(c)));
        }
        return EnvironmentMapper.toDto(repository.save(environment));
    }

    /**
     * Update an Environment's own fields (name, memo). Components are not replaced here — they are
     * curated through {@link #addComponent}/{@link #updateComponent}/{@link #removeComponent} so each
     * change is an explicit, scoped operation rather than a silent wholesale swap.
     */
    @Transactional
    public EnvironmentDto updateEnvironment(Long id, EnvironmentRequest request) {
        Environment environment = require(id);
        environment.setName(request.name());
        environment.setMemo(request.memo());
        environment.setSeeUrl(normalizeSeeUrl(request.seeUrl()));
        return EnvironmentMapper.toDto(environment);
    }

    /** Delete an Environment; cascade + orphan removal drop its Components, shared resources stay. */
    @Transactional
    public void deleteEnvironment(Long id) {
        repository.delete(require(id));
    }

    /** Add a Component to an existing Environment and return it (with its assigned id). */
    @Transactional
    public ComponentDto addComponent(Long environmentId, ComponentRequest request) {
        Environment environment = require(environmentId);
        Component component = EnvironmentMapper.toDomain(request);
        environment.addComponent(component);
        repository.flush(); // assign the Component's sequence id before mapping out
        return EnvironmentMapper.toDto(component);
    }

    /** Update one Component's curated fields, scoped to its owning Environment. */
    @Transactional
    public ComponentDto updateComponent(Long environmentId, Long componentId, ComponentRequest request) {
        Component component = requireComponent(environmentId, componentId);
        EnvironmentMapper.applyTo(component, request);
        return EnvironmentMapper.toDto(component);
    }

    /** Remove one Component from its owning Environment (orphan removal deletes it). */
    @Transactional
    public void removeComponent(Long environmentId, Long componentId) {
        Environment environment = require(environmentId);
        Component component = environment.findComponent(componentId)
                .orElseThrow(() -> new ComponentNotFoundException(componentId));
        environment.removeComponent(component);
    }

    /** Lenient by design: legacy SEE links may be odd-shaped, so no scheme check — just trim/blank→null. */
    private static String normalizeSeeUrl(String seeUrl) {
        if (seeUrl == null) {
            return null;
        }
        String trimmed = seeUrl.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private Environment require(Long id) {
        return repository.findById(id).orElseThrow(() -> new EnvironmentNotFoundException(id));
    }

    private Component requireComponent(Long environmentId, Long componentId) {
        return require(environmentId).findComponent(componentId)
                .orElseThrow(() -> new ComponentNotFoundException(componentId));
    }
}
