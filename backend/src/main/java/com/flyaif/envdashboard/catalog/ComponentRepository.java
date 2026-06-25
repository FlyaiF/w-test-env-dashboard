package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Direct access to a {@link Component} for the linking use-case (setting its runs-on Server and uses
 * Databases). Full Component CRUD through the Environment aggregate is slice 03.
 */
public interface ComponentRepository extends JpaRepository<Component, Long> {
}
