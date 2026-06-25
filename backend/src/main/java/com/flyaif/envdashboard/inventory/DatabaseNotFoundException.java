package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.shared.NotFoundException;

/** Thrown when a Database is requested by an id that does not exist. */
public class DatabaseNotFoundException extends NotFoundException {

    public DatabaseNotFoundException(Long id) {
        super("Database not found: " + id);
    }
}
