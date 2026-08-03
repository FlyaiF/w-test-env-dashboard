package com.flyaif.envdashboard.access;

import com.flyaif.envdashboard.access.domain.DatabaseSecret;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Set;

/** Persistence for a Database's encrypted login secret, keyed by the Database id. */
public interface DatabaseSecretRepository extends JpaRepository<DatabaseSecret, Long> {

    /** Ids only — never loads ciphertext, so presence checks stay outside the crypto path. */
    @Query("select s.databaseId from DatabaseSecret s")
    Set<Long> allDatabaseIds();
}
