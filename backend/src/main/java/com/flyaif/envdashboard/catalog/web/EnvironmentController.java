package com.flyaif.envdashboard.catalog.web;

import com.flyaif.envdashboard.catalog.EnvironmentService;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.ComponentRequest;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentRequest;
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

/**
 * Read + curation endpoint for the Environment Catalog. Holds no model logic — the service maps the
 * aggregate to its published DTO contract (inside the transaction) and this just returns it. Component
 * routes are nested under their Environment because a Component is only ever reached through its
 * owning aggregate root; the runs-on / uses links keep their own endpoint ({@link ComponentLinkController}).
 */
@RestController
@RequestMapping("/api/environments")
public class EnvironmentController {

    private final EnvironmentService service;

    public EnvironmentController(EnvironmentService service) {
        this.service = service;
    }

    @GetMapping
    public List<EnvironmentDto> list() {
        return service.listEnvironments();
    }

    @GetMapping("/{id}")
    public EnvironmentDto getById(@PathVariable Long id) {
        return service.getEnvironment(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public EnvironmentDto create(@Valid @RequestBody EnvironmentRequest request) {
        return service.createEnvironment(request);
    }

    @PutMapping("/{id}")
    public EnvironmentDto update(@PathVariable Long id, @Valid @RequestBody EnvironmentRequest request) {
        return service.updateEnvironment(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        service.deleteEnvironment(id);
    }

    @PostMapping("/{environmentId}/components")
    @ResponseStatus(HttpStatus.CREATED)
    public ComponentDto addComponent(@PathVariable Long environmentId,
                                     @Valid @RequestBody ComponentRequest request) {
        return service.addComponent(environmentId, request);
    }

    @PutMapping("/{environmentId}/components/{componentId}")
    public ComponentDto updateComponent(@PathVariable Long environmentId,
                                        @PathVariable Long componentId,
                                        @Valid @RequestBody ComponentRequest request) {
        return service.updateComponent(environmentId, componentId, request);
    }

    @DeleteMapping("/{environmentId}/components/{componentId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteComponent(@PathVariable Long environmentId, @PathVariable Long componentId) {
        service.removeComponent(environmentId, componentId);
    }
}
