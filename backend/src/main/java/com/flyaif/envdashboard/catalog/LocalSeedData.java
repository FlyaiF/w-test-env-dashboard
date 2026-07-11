package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.access.SecretStore;
import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import com.flyaif.envdashboard.catalog.domain.VersionProbeKind;
import com.flyaif.envdashboard.inventory.DatabaseRepository;
import com.flyaif.envdashboard.inventory.ServerRepository;
import com.flyaif.envdashboard.inventory.domain.ConnectionDescriptor;
import com.flyaif.envdashboard.inventory.domain.Database;
import com.flyaif.envdashboard.inventory.domain.DatabaseType;
import com.flyaif.envdashboard.inventory.domain.Server;
import com.flyaif.envdashboard.inventory.domain.ServerOs;
import com.flyaif.envdashboard.inventory.domain.SshAccess;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;

import java.time.Instant;
import java.util.Set;

/**
 * Seeds a couple of demo Environments — plus shared Servers/Databases and the links between them — on
 * the {@code local} profile so the read and Resource Inventory APIs are immediately demoable on a
 * fresh H2. It stays disabled when the one-time {@code import} profile is also active, so a local
 * migration rehearsal still targets an empty schema. Never active in prod.
 *
 * <p>Registered as a Spring bean via the fully-qualified {@code @org.springframework.stereotype.Component}
 * to avoid colliding with the domain {@link Component} type imported above.
 */
@Profile("local & !import")
@org.springframework.stereotype.Component
public class LocalSeedData implements CommandLineRunner {

    private final EnvironmentRepository environments;
    private final ServerRepository servers;
    private final DatabaseRepository databases;
    private final SecretStore secrets;

    public LocalSeedData(EnvironmentRepository environments,
                         ServerRepository servers,
                         DatabaseRepository databases,
                         SecretStore secrets) {
        this.environments = environments;
        this.servers = servers;
        this.databases = databases;
        this.secrets = secrets;
    }

    @Override
    public void run(String... args) {
        if (environments.count() > 0) {
            return;
        }

        // Shared resources, saved first so Components can reference them by ID.
        Server linuxHost = servers.save(new Server("10.0.1.10", ServerOs.LINUX,
                new SshAccess("10.0.1.10", 22, "deploy")));
        Server windowsHost = servers.save(new Server("10.0.1.20", ServerOs.WINDOWS,
                new SshAccess("10.0.1.20", 22, "Administrator")));
        // A shared business DB used by more than one Environment (demonstrates the reverse lookup).
        Database businessDb = databases.save(new Database("business", DatabaseType.ORACLE,
                new ConnectionDescriptor("10.0.2.5", 1521, "ORCL", "app")));
        Database configDb = databases.save(new Database("config", DatabaseType.DAMENG,
                new ConnectionDescriptor("10.0.2.6", 5236, "CFG", "cfg")));

        // Demo secrets, stored encrypted at rest (ADR-0005) so the credential-brokering endpoints
        // return something to launch a tool with on a fresh local H2.
        secrets.putServerSecret(linuxHost.getId(), "deploy-pw");
        secrets.putServerSecret(windowsHost.getId(), "Admin-pw");
        secrets.putDatabaseSecret(businessDb.getId(), "app-pw");
        secrets.putDatabaseSecret(configDb.getId(), "cfg-pw");

        Environment alpha = new Environment("测试环境 Alpha", "QA 主测试环境");
        Component alphaGateway = new Component(ComponentRole.GATEWAY);
        alphaGateway.setVersion("2.4.1");
        alphaGateway.setVersionUpdatedAt(Instant.parse("2026-06-20T08:30:00Z"));
        alphaGateway.setLogLocation("/var/log/nginx/gateway.log");
        alphaGateway.setListenPort(443);
        alphaGateway.setProtocol("https");
        alphaGateway.setUrl("https://alpha-gw.test.internal/health");
        alphaGateway.setServerId(linuxHost.getId());
        alphaGateway.setVersionProbe(VersionProbeKind.HTTP); // version read from its HTTP endpoint
        alpha.addComponent(alphaGateway);

        Component alphaApp = new Component(ComponentRole.APP);
        alphaApp.setVersion("2.4.0");
        alphaApp.setVersionUpdatedAt(Instant.parse("2026-06-19T14:05:00Z"));
        alphaApp.setLogLocation("/opt/app/logs/app.log");
        alphaApp.setListenPort(8080);
        alphaApp.setProtocol("http");
        alphaApp.setServerId(linuxHost.getId());
        alphaApp.setDatabaseIds(Set.of(businessDb.getId(), configDb.getId()));
        alphaApp.setVersionProbe(VersionProbeKind.DB);       // version read from its business DB
        alpha.addComponent(alphaApp);

        Component alphaUi = new Component(ComponentRole.UI);
        alphaUi.setVersion("2.4.1");
        alphaUi.setListenPort(80);
        alphaUi.setProtocol("http");
        alphaUi.setServerId(windowsHost.getId());
        alphaUi.setVersionProbe(VersionProbeKind.NONE);      // static UI, no version to collect
        alpha.addComponent(alphaUi);

        Environment beta = new Environment("测试环境 Beta", null);
        Component betaApp = new Component(ComponentRole.APP);
        betaApp.setVersion("3.0.0-rc2");
        betaApp.setVersionUpdatedAt(Instant.parse("2026-06-24T11:00:00Z"));
        betaApp.setLogLocation("/opt/app/logs/app.log");
        betaApp.setListenPort(8080);
        betaApp.setProtocol("http");
        betaApp.setServerId(linuxHost.getId());
        betaApp.setDatabaseIds(Set.of(businessDb.getId()));
        betaApp.setVersionProbe(VersionProbeKind.DB);
        beta.addComponent(betaApp);

        Component betaProto = new Component(ComponentRole.PRIVATE_PROTO);
        betaProto.setListenPort(9100);
        betaProto.setProtocol("tcp");
        betaProto.setVersionProbe(VersionProbeKind.NONE);
        beta.addComponent(betaProto);

        environments.save(alpha);
        environments.save(beta);
    }
}
