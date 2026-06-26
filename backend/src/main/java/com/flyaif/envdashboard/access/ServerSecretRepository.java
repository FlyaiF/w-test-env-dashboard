package com.flyaif.envdashboard.access;

import com.flyaif.envdashboard.access.domain.ServerSecret;
import org.springframework.data.jpa.repository.JpaRepository;

/** Persistence for a Server's encrypted SSH secret, keyed by the Server id. */
public interface ServerSecretRepository extends JpaRepository<ServerSecret, Long> {
}
