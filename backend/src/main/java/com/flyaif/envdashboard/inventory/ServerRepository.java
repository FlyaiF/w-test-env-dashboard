package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.inventory.domain.Server;
import org.springframework.data.jpa.repository.JpaRepository;

/** Persistence for the shared {@link Server} aggregate. */
public interface ServerRepository extends JpaRepository<Server, Long> {
}
