package com.flyaif.envdashboard.shared;

/**
 * A shared resource cannot be deleted because Components still reference it. Mapped to 409
 * problem+json — the conflict is surfaced rather than silently cascaded (ADR-0003).
 */
public class ResourceInUseException extends RuntimeException {

    public ResourceInUseException(String message) {
        super(message);
    }
}
