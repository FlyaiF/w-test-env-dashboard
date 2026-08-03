package com.flyaif.envdashboard.collection.machine;

/**
 * A reach to a machine (HTTP / JDBC) failed. Probes let this propagate; the collector turns it into a
 * per-Component {@code FAILED} result so one unreachable host never blanks its siblings.
 */
public class MachineAccessException extends RuntimeException {

    public MachineAccessException(String message) {
        super(message);
    }

    public MachineAccessException(String message, Throwable cause) {
        super(message, cause);
    }
}
