package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

/**
 * Direct access to a {@link Component} for the linking use-case (setting its runs-on Server and uses
 * Databases). Full Component CRUD through the Environment aggregate is slice 03.
 */
public interface ComponentRepository extends JpaRepository<Component, Long> {

    /** Per-Server count of Components running on it: {@code [serverId, count]} rows. */
    @Query("select c.serverId, count(c) from Component c where c.serverId is not null group by c.serverId")
    List<Object[]> countGroupedByServer();

    /** Per-Database count of Components using it: {@code [databaseId, count]} rows. */
    @Query("select d, count(c) from Component c join c.databaseIds d group by d")
    List<Object[]> countGroupedByDatabase();
}
