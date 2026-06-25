package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Environment;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * Persistence for the {@link Environment} aggregate. Components are loaded with their Environment
 * (entity graph) so the read path serves a complete aggregate without lazy-loading surprises.
 */
public interface EnvironmentRepository extends JpaRepository<Environment, Long> {

    @Override
    @EntityGraph(attributePaths = "components")
    List<Environment> findAll();

    @Override
    @EntityGraph(attributePaths = "components")
    Optional<Environment> findById(Long id);
}
