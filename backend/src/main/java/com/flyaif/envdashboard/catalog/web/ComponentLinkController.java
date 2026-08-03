package com.flyaif.envdashboard.catalog.web;

import com.flyaif.envdashboard.catalog.ComponentLinkingService;
import com.flyaif.envdashboard.catalog.web.dto.ComponentDto;
import com.flyaif.envdashboard.catalog.web.dto.ComponentLinksRequest;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Links a Component to the Resource Inventory. Full Component editing lands with the catalog write
 * path (slice 03); this slice exposes only the runs-on / uses links.
 */
@RestController
@RequestMapping("/api/components")
public class ComponentLinkController {

    private final ComponentLinkingService linking;

    public ComponentLinkController(ComponentLinkingService linking) {
        this.linking = linking;
    }

    @PutMapping("/{id}/links")
    public ComponentDto setLinks(@PathVariable Long id, @RequestBody ComponentLinksRequest request) {
        return linking.setLinks(id, request.serverId(), request.databaseIds());
    }
}
