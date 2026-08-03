package com.flyaif.envdashboard.access;

import com.flyaif.envdashboard.access.domain.ServerSecret;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Set;

/** Persistence for a Server's encrypted SSH secret, keyed by the Server id. */
public interface ServerSecretRepository extends JpaRepository<ServerSecret, Long> {

    /** Ids only — never loads ciphertext, so presence checks stay outside the crypto path. */
    @Query("select s.serverId from ServerSecret s")
    Set<Long> allServerIds();
}
