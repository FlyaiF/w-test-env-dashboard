package com.flyaif.envdashboard.inventory.web;

import com.flyaif.envdashboard.catalog.EnvironmentService;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.inventory.ServerService;
import com.flyaif.envdashboard.inventory.web.dto.ServerDto;
import com.flyaif.envdashboard.inventory.web.dto.ServerRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** CRUD for shared Servers, plus the "which Environments run on this Server?" reverse lookup. */
@RestController
@RequestMapping("/api/servers")
public class ServerController {

    private final ServerService servers;
    private final EnvironmentService environments;

    public ServerController(ServerService servers, EnvironmentService environments) {
        this.servers = servers;
        this.environments = environments;
    }

    @GetMapping
    public List<ServerDto> list() {
        return servers.list();
    }

    @GetMapping("/{id}")
    public ServerDto get(@PathVariable Long id) {
        return servers.get(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ServerDto create(@Valid @RequestBody ServerRequest request) {
        return servers.create(request);
    }

    @PutMapping("/{id}")
    public ServerDto update(@PathVariable Long id, @Valid @RequestBody ServerRequest request) {
        return servers.update(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        servers.delete(id);
    }

    /** Reverse lookup (ADR-0003): Environments with a Component running on this Server. */
    @GetMapping("/{id}/environments")
    public List<EnvironmentDto> environmentsOnServer(@PathVariable Long id) {
        servers.get(id); // 404 if the Server does not exist
        return environments.environmentsOnServer(id);
    }
}
