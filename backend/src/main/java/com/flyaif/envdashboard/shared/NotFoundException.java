package com.flyaif.envdashboard.shared;

/** A requested resource does not exist. Mapped to 404 problem+json by the API exception handler. */
public class NotFoundException extends RuntimeException {

    public NotFoundException(String message) {
        super(message);
    }
}
