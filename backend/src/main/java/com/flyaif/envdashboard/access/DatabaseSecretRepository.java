package com.flyaif.envdashboard.access;

import com.flyaif.envdashboard.access.domain.DatabaseSecret;
import org.springframework.data.jpa.repository.JpaRepository;

/** Persistence for a Database's encrypted login secret, keyed by the Database id. */
public interface DatabaseSecretRepository extends JpaRepository<DatabaseSecret, Long> {
}
