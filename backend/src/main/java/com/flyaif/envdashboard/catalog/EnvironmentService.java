package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.web.EnvironmentMapper;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * Read use-cases for the Environment Catalog. Mapping to the published DTO happens here, inside the
 * read transaction, so lazily-loaded parts of the aggregate (Components and their Database links)
 * resolve without leaking persistence concerns into the web layer. The write path lands in slice 03.
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
}
