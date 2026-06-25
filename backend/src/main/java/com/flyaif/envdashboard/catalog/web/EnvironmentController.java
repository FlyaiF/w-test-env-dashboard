package com.flyaif.envdashboard.catalog.web;

import com.flyaif.envdashboard.catalog.EnvironmentNotFoundException;
import com.flyaif.envdashboard.catalog.EnvironmentService;
import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Thin read endpoint for the Environment Catalog. Holds no model logic — it delegates to the
 * service and maps the aggregate to its published DTO contract.
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
        return service.listEnvironments().stream()
                .map(EnvironmentMapper::toDto)
                .toList();
    }

    @GetMapping("/{id}")
    public EnvironmentDto getById(@PathVariable Long id) {
        return EnvironmentMapper.toDto(service.getEnvironment(id));
    }

    @ResponseStatus(HttpStatus.NOT_FOUND)
    @ExceptionHandler(EnvironmentNotFoundException.class)
    public ProblemDetail handleNotFound(EnvironmentNotFoundException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Environment not found");
        return problem;
    }
}
