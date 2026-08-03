package com.flyaif.envdashboard.access;

import com.flyaif.envdashboard.access.web.dto.DatabaseCredentialDto;
import com.flyaif.envdashboard.access.web.dto.ServerCredentialDto;
import com.flyaif.envdashboard.inventory.DatabaseNotFoundException;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.JdbcUrlBuilder;
import com.flyaif.envdashboard.inventory.ServerNotFoundException;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.SshAccess;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The Access Brokering context (ADR-0005): stores Server/Database secrets encrypted at rest and
 * delivers a credential bundle — connection descriptor plus decrypted secret — to the client on
 * demand. It is deliberately the only path that decrypts for delivery; secrets never ride along the
 * Resource Inventory read DTOs, so the catalog UI cannot leak them.
 *
 * <p>Writes validate that the target resource exists first (404, not an FK violation). Brokering a
 * resource that has no stored secret returns the descriptor with a null secret rather than failing —
 * the resource may use trust auth or have its secret set later.
 */
@Service
@Transactional
public class AccessBrokerService {

    private final ServerRepository servers;
    private final DatabaseRepository databases;
    private final SecretStore secrets;

    public AccessBrokerService(ServerRepository servers,
                               DatabaseRepository databases,
                               SecretStore secrets) {
        this.servers = servers;
        this.databases = databases;
        this.secrets = secrets;
    }

    public void storeServerSecret(Long serverId, String plaintext) {
        requireServer(serverId);
        secrets.putServerSecret(serverId, plaintext);
    }

    public void storeDatabaseSecret(Long databaseId, String plaintext) {
        requireDatabase(databaseId);
        secrets.putDatabaseSecret(databaseId, plaintext);
    }

    @Transactional(readOnly = true)
    public ServerCredentialDto brokerServerCredential(Long serverId) {
        Server server = requireServer(serverId);
        SshAccess ssh = server.getSsh();
        String host = ssh != null && ssh.getHost() != null ? ssh.getHost() : server.getHost();
        Integer port = ssh == null ? null : ssh.getPort();
        String username = ssh == null ? null : ssh.getUsername();
        String secret = secrets.serverSecret(serverId).orElse(null);
        return new ServerCredentialDto(serverId, host, port, username, secret);
    }

    @Transactional(readOnly = true)
    public DatabaseCredentialDto brokerDatabaseCredential(Long databaseId) {
        Database database = requireDatabase(databaseId);
        ConnectionDescriptor conn = database.getConnection();
        String secret = secrets.databaseSecret(databaseId).orElse(null);
        return new DatabaseCredentialDto(
                databaseId,
                database.getType() == null ? null : database.getType().name(),
                conn == null ? null : conn.getHost(),
                conn == null ? null : conn.getPort(),
                conn == null ? null : conn.getServiceName(),
                conn == null ? null : conn.getUsername(),
                JdbcUrlBuilder.forDatabase(database),
                secret);
    }

    private Server requireServer(Long id) {
        return servers.findById(id).orElseThrow(() -> new ServerNotFoundException(id));
    }

    private Database requireDatabase(Long id) {
        return databases.findById(id).orElseThrow(() -> new DatabaseNotFoundException(id));
    }
}
