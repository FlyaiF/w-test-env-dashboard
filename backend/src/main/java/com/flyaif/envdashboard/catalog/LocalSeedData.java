package com.flyaif.envdashboard.catalog;

import com.flyaif.envdashboard.catalog.domain.Component;
import com.flyaif.envdashboard.catalog.domain.ComponentRole;
import com.flyaif.envdashboard.catalog.domain.Environment;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;

import java.time.Instant;

/**
 * Seeds a couple of demo Environments on the {@code local} profile so the read API is immediately
 * demoable on a fresh H2. Never active in prod — keeps Oracle migrations free of seed rows.
 *
 * <p>Registered as a Spring bean via the fully-qualified {@code @org.springframework.stereotype.Component}
 * to avoid colliding with the domain {@link Component} type imported above.
 */
@Profile("local")
@org.springframework.stereotype.Component
public class LocalSeedData implements CommandLineRunner {

    private final EnvironmentRepository repository;

    public LocalSeedData(EnvironmentRepository repository) {
        this.repository = repository;
    }

    @Override
    public void run(String... args) {
        if (repository.count() > 0) {
            return;
        }

        Environment alpha = new Environment("测试环境 Alpha", "QA 主测试环境");
        Component alphaGateway = new Component(ComponentRole.GATEWAY);
        alphaGateway.setVersion("2.4.1");
        alphaGateway.setDeployTime(Instant.parse("2026-06-20T08:30:00Z"));
        alphaGateway.setLogLocation("/var/log/nginx/gateway.log");
        alphaGateway.setListenPort(443);
        alphaGateway.setProtocol("https");
        alphaGateway.setUrl("https://alpha-gw.test.internal/health");
        alpha.addComponent(alphaGateway);

        Component alphaApp = new Component(ComponentRole.APP);
        alphaApp.setVersion("2.4.0");
        alphaApp.setDeployTime(Instant.parse("2026-06-19T14:05:00Z"));
        alphaApp.setLogLocation("/opt/app/logs/app.log");
        alphaApp.setListenPort(8080);
        alphaApp.setProtocol("http");
        alpha.addComponent(alphaApp);

        Component alphaUi = new Component(ComponentRole.UI);
        alphaUi.setVersion("2.4.1");
        alphaUi.setListenPort(80);
        alphaUi.setProtocol("http");
        alpha.addComponent(alphaUi);

        Environment beta = new Environment("测试环境 Beta", null);
        Component betaApp = new Component(ComponentRole.APP);
        betaApp.setVersion("3.0.0-rc2");
        betaApp.setDeployTime(Instant.parse("2026-06-24T11:00:00Z"));
        betaApp.setLogLocation("/opt/app/logs/app.log");
        betaApp.setListenPort(8080);
        betaApp.setProtocol("http");
        beta.addComponent(betaApp);

        Component betaProto = new Component(ComponentRole.PRIVATE_PROTO);
        betaProto.setListenPort(9100);
        betaProto.setProtocol("tcp");
        beta.addComponent(betaProto);

        repository.save(alpha);
        repository.save(beta);
    }
}
