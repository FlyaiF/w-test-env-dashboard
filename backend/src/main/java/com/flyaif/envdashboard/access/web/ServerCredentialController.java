package com.flyaif.envdashboard.access.web;

import com.flyaif.envdashboard.access.AccessBrokerService;
import com.flyaif.envdashboard.access.web.dto.SecretRequest;
import com.flyaif.envdashboard.access.web.dto.ServerCredentialDto;
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
 * Access Brokering for Servers (ADR-0005). The SSH secret goes in encrypted (PUT) and a credential
 * bundle comes out on demand (GET) — the GET is the only way the client obtains a secret, and it
 * persists nothing. A secret is never returned on the Server's own Inventory DTO, only here.
 */
@RestController
@RequestMapping("/api/servers")
public class ServerCredentialController {

    private final AccessBrokerService broker;

    public ServerCredentialController(AccessBrokerService broker) {
        this.broker = broker;
    }

    @PutMapping("/{id}/secret")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void setSecret(@PathVariable Long id, @Valid @RequestBody SecretRequest request) {
        broker.storeServerSecret(id, request.secret());
    }

    @GetMapping("/{id}/credentials")
    public ServerCredentialDto credentials(@PathVariable Long id) {
        return broker.brokerServerCredential(id);
    }
}
