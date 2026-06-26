package com.flyaif.envdashboard.access.web;

import com.flyaif.envdashboard.access.AccessBrokerService;
import com.flyaif.envdashboard.access.web.dto.DatabaseCredentialDto;
import com.flyaif.envdashboard.access.web.dto.SecretRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * Access Brokering for Databases (ADR-0005). The login secret goes in encrypted (PUT) and a credential
 * bundle — connection descriptor, ready-to-use {@code jdbcUrl}, and decrypted secret — comes out on
 * demand (GET). The secret is never returned on the Database's own Inventory DTO, only here.
 */
@RestController
@RequestMapping("/api/databases")
public class DatabaseCredentialController {

    private final AccessBrokerService broker;

    public DatabaseCredentialController(AccessBrokerService broker) {
        this.broker = broker;
    }

    @PutMapping("/{id}/secret")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void setSecret(@PathVariable Long id, @Valid @RequestBody SecretRequest request) {
        broker.storeDatabaseSecret(id, request.secret());
    }

    @GetMapping("/{id}/credentials")
    public DatabaseCredentialDto credentials(@PathVariable Long id) {
        return broker.brokerDatabaseCredential(id);
    }
}
