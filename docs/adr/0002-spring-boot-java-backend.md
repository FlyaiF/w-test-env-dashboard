# Build the backend in Spring Boot (Java) and retire the Go sidecar

The monitored applications are themselves Spring Boot, the team lives in Java, and JDBC has the
richest driver ecosystem for the databases we must reach (Oracle, Dameng, OceanBase). The clearest
signal: the existing Go sidecar already shells out to a **Java helper** for OceanBase — the Go design
was fighting the grain. We build a fresh Spring Boot backend and retire the Go sidecar entirely
rather than evolve it, because the one hard asset (multi-DB connectivity) is better served by JDBC.

GraalVM **native-image** is desirable for startup/deployment but reflection-sensitive third-party
JDBC drivers (notably Dameng/OceanBase) may not be native-image-clean. JVM mode is the default;
native-image is an optimisation validated per-driver, never a build blocker.
