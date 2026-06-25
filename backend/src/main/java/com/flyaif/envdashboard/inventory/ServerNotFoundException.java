package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.shared.NotFoundException;

/** Thrown when a Server is requested by an id that does not exist. */
public class ServerNotFoundException extends NotFoundException {

    public ServerNotFoundException(Long id) {
        super("Server not found: " + id);
    }
}
