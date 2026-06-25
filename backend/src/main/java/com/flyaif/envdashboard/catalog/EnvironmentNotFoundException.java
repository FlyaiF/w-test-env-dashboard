package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.shared.NotFoundException;

/** Thrown when an Environment is requested by an id that does not exist. */
public class EnvironmentNotFoundException extends NotFoundException {

    public EnvironmentNotFoundException(Long id) {
        super("Environment not found: " + id);
    }
}
