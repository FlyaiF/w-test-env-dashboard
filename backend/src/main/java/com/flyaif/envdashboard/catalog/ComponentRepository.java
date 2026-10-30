package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.LivenessStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

/**
 * Direct access to a {@link Component} for the linking use-case (setting its runs-on Server and uses
 * Databases) and for recording its running state. Full Component CRUD through the Environment
 * aggregate is slice 03.
 */
public interface ComponentRepository extends JpaRepository<Component, Long> {

    /** Per-Server count of Components running on it: {@code [serverId, count]} rows. */
    @Query("select c.serverId, count(c) from Component c where c.serverId is not null group by c.serverId")
    List<Object[]> countGroupedByServer();

    /** Per-Database count of Components using it: {@code [databaseId, count]} rows. */
    @Query("select d, count(c) from Component c join c.databaseIds d group by d")
    List<Object[]> countGroupedByDatabase();

    /**
     * Records one liveness observation, only if the Component still has the URL that was checked and
     * no newer observation has landed meanwhile; {@code livenessChangedAt} moves only when the status
     * does. One atomic statement, so a slow check can never overwrite a later one. Returns rows written.
     */
    @Modifying
    @Query("""
            update Component c set
                c.livenessChangedAt = case when c.liveness = :status then c.livenessChangedAt else :observedAt end,
                c.liveness = :status,
                c.livenessDetail = :detail,
                c.livenessCheckedAt = :observedAt
            where c.id = :id and c.url = :url
                and (c.livenessCheckedAt is null or c.livenessCheckedAt < :observedAt)""")
    int recordLiveness(@Param("id") Long id,
                       @Param("url") String url,
                       @Param("status") LivenessStatus status,
                       @Param("detail") String detail,
                       @Param("observedAt") Instant observedAt);

    /** Clears the running state of a Component that (still) has no URL to check. Returns rows written. */
    @Modifying
    @Query("""
            update Component c set
                c.liveness = null, c.livenessDetail = null,
                c.livenessCheckedAt = null, c.livenessChangedAt = null
            where c.id = :id and (c.url is null or trim(c.url) is null or trim(c.url) = '')
                and c.livenessCheckedAt is not null""")
    int clearLiveness(@Param("id") Long id);
}
