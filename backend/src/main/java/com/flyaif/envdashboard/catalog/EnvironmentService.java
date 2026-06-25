package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Environment;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * Read use-cases for the Environment Catalog. The write path lands in slice 03.
 */
@Service
@Transactional(readOnly = true)
public class EnvironmentService {

    private final EnvironmentRepository repository;

    public EnvironmentService(EnvironmentRepository repository) {
        this.repository = repository;
    }

    public List<Environment> listEnvironments() {
        return repository.findAll();
    }

    public Environment getEnvironment(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new EnvironmentNotFoundException(id));
    }
}
