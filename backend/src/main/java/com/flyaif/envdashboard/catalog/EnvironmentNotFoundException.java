package com.flyaif.envdashboard.catalog;

/** Thrown when an Environment is requested by an id that does not exist. */
public class EnvironmentNotFoundException extends RuntimeException {

    public EnvironmentNotFoundException(Long id) {
        super("Environment not found: " + id);
    }
}
