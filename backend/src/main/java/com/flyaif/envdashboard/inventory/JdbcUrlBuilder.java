package com.flyaif.envdashboard.inventory;

import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;

/**
 * Builds the JDBC URL for a {@link Database} from its non-secret connection descriptor and engine
 * type. Shared by Version Collection (to open probe connections) and Access Brokering (to hand the
 * client a ready-to-use connect string for its own DB tool), so the per-engine URL shape lives once.
 */
public final class JdbcUrlBuilder {

    private JdbcUrlBuilder() {
    }

    /**
     * The JDBC URL for the database's engine, or {@code null} when one cannot be formed — no
     * connection descriptor, or a type with no known driver mapping ({@link DatabaseType#OTHER}).
     */
    public static String forDatabase(Database database) {
        ConnectionDescriptor c = database.getConnection();
        if (c == null) {
            return null;
        }
        DatabaseType type = database.getType() == null ? DatabaseType.OTHER : database.getType();
        String host = c.getHost();
        Integer port = c.getPort() == null ? defaultPort(type) : c.getPort();
        String service = c.getServiceName();
        return switch (type) {
            case ORACLE -> "jdbc:oracle:thin:@//" + host + ":" + port + "/" + service;
            case DAMENG -> "jdbc:dm://" + host + ":" + port;
            // OceanBase Connector/J only accepts jdbc:oceanbase[:hamode]://host:port/db, where
            // hamode is an HA option such as loadbalance — "oracle" is not a valid token there.
            // MySQL vs Oracle compatibility is decided by the tenant in the username
            // (user@tenant), never by the URL.
            case OCEANBASE -> "jdbc:oceanbase://" + host + ":" + port + "/" + service;
            case OTHER -> null;
        };
    }

    /** The conventional engine port used when a legacy descriptor omitted it; null for OTHER. */
    public static Integer defaultPort(DatabaseType type) {
        if (type == null) {
            return null;
        }
        return switch (type) {
            case ORACLE -> 1521;
            case DAMENG -> 5236;
            case OCEANBASE -> 2881;
            case OTHER -> null;
        };
    }
}
