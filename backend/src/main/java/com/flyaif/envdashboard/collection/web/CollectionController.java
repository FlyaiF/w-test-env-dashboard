package com.flyaif.envdashboard.collection.web;

import com.flyaif.envdashboard.catalog.web.dto.EnvironmentDto;
import com.flyaif.envdashboard.collection.CollectionService;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The manual "refresh now" entry point for Version Collection: triggers an on-demand collect of one
 * Environment and returns its freshly-collected view. The scheduled sweep ({@link
 * com.flyaif.envdashboard.collection.CollectionScheduler}) covers everything in the background.
 */
@RestController
@RequestMapping("/api/environments")
public class CollectionController {

    private final CollectionService collection;

    public CollectionController(CollectionService collection) {
        this.collection = collection;
    }

    /** Collect this Environment's Components now; 404 (problem+json) for an unknown id. */
    @PostMapping("/{id}/refresh")
    public EnvironmentDto refresh(@PathVariable Long id) {
        return collection.refresh(id);
    }
}
