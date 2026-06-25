package com.flyaif.envdashboard.inventory.web;

import com.flyaif.envdashboard.catalog.EnvironmentService;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.inventory.DatabaseService;
import com.flyaif.envdashboard.inventory.web.dto.DatabaseDto;
import com.flyaif.envdashboard.inventory.web.dto.DatabaseRequest;
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

/** CRUD for shared Databases, plus the "which Environments use this Database?" reverse lookup. */
@RestController
@RequestMapping("/api/databases")
public class DatabaseController {

    private final DatabaseService databases;
    private final EnvironmentService environments;

    public DatabaseController(DatabaseService databases, EnvironmentService environments) {
        this.databases = databases;
        this.environments = environments;
    }

    @GetMapping
    public List<DatabaseDto> list() {
        return databases.list();
    }

    @GetMapping("/{id}")
    public DatabaseDto get(@PathVariable Long id) {
        return databases.get(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public DatabaseDto create(@Valid @RequestBody DatabaseRequest request) {
        return databases.create(request);
    }

    @PutMapping("/{id}")
    public DatabaseDto update(@PathVariable Long id, @Valid @RequestBody DatabaseRequest request) {
        return databases.update(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        databases.delete(id);
    }

    /** Reverse lookup (ADR-0003): Environments with a Component using this Database. */
    @GetMapping("/{id}/environments")
    public List<EnvironmentDto> environmentsUsingDatabase(@PathVariable Long id) {
        databases.get(id); // 404 if the Database does not exist
        return environments.environmentsUsingDatabase(id);
    }
}
