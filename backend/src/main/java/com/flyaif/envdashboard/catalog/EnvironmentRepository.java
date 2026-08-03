package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Environment;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

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

    /** Environments with at least one Component running on the given Server. */
    @EntityGraph(attributePaths = "components")
    List<Environment> findDistinctByComponentsServerId(Long serverId);

    /** Environments with at least one Component using the given Database (by ID). */
    @EntityGraph(attributePaths = "components")
    @Query("select distinct e from Environment e join e.components c where :databaseId member of c.databaseIds")
    List<Environment> findDistinctByDatabaseId(@Param("databaseId") Long databaseId);

    /** Whether any Component runs on the given Server — guards Server deletion (ADR-0003). */
    boolean existsByComponentsServerId(Long serverId);

    /** Whether any Component uses the given Database — guards Database deletion (ADR-0003). */
    @Query("select (count(c) > 0) from Component c where :databaseId member of c.databaseIds")
    boolean existsByDatabaseId(@Param("databaseId") Long databaseId);
}
