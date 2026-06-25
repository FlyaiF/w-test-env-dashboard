package com.flyaif.envdashboard.catalog.web;

import com.flyaif.envdashboard.catalog.EnvironmentService;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Thin read endpoint for the Environment Catalog. Holds no model logic — the service maps the
 * aggregate to its published DTO contract (inside the read transaction) and this just returns it.
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
}
