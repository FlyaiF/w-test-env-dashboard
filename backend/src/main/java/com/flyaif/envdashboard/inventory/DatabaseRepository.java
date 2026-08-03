package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.inventory.domain.Database;
import org.springframework.data.jpa.repository.JpaRepository;

/** Persistence for the shared {@link Database} aggregate. */
public interface DatabaseRepository extends JpaRepository<Database, Long> {
}
