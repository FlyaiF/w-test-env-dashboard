package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.shared.NotFoundException;

/** Thrown when a Component is requested by an id that does not exist. */
public class ComponentNotFoundException extends NotFoundException {

    public ComponentNotFoundException(Long id) {
        super("Component not found: " + id);
    }
}
