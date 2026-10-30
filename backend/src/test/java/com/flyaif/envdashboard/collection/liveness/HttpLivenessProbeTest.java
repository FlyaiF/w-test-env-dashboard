package com.flyaif.envdashboard.collection.liveness;

import com.flyaif.envdashboard.catalog.domain.LivenessStatus;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Exercises the real JDK HTTP client against a local server, so the classification matches what the
 * client actually throws (its socket errors arrive wrapped, not as the raw exceptions).
 */
class HttpLivenessProbeTest {

    private HttpServer server;
    private HttpLivenessProbe probe;

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        server.createContext("/ok", exchange -> {
            exchange.sendResponseHeaders(200, -1);
            exchange.close();
        });
        server.createContext("/login-redirect", exchange -> {
            exchange.getResponseHeaders().add("Location", "http://cas.invalid/login");
            exchange.sendResponseHeaders(302, -1);
            exchange.close();
        });
        server.createContext("/bad-gateway", exchange -> {
            exchange.sendResponseHeaders(502, -1);
            exchange.close();
        });
        server.start();

        LivenessProperties properties = new LivenessProperties();
        properties.setConnectTimeout(Duration.ofSeconds(1));
        properties.setRequestTimeout(Duration.ofSeconds(1));
        probe = new HttpLivenessProbe(properties);
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    private String base() {
        return "http://127.0.0.1:" + server.getAddress().getPort();
    }

    @Test
    void successIsUp() {
        assertThat(probe.check(base() + "/ok")).isEqualTo(LivenessCheck.up("HTTP 200"));
    }

    @Test
    void redirectIsUpAndNotFollowed() {
        // Following it would hit an unresolvable host; staying UP proves the redirect was not chased.
        assertThat(probe.check(base() + "/login-redirect")).isEqualTo(LivenessCheck.up("HTTP 302"));
    }

    @Test
    void notFoundStillCountsAsServing() {
        assertThat(probe.check(base() + "/missing").status()).isEqualTo(LivenessStatus.UP);
    }

    @Test
    void serverErrorIsDown() {
        assertThat(probe.check(base() + "/bad-gateway")).isEqualTo(LivenessCheck.down("HTTP 502"));
    }

    @Test
    void refusedConnectionIsDown() throws IOException {
        int closedPort;
        try (ServerSocket socket = new ServerSocket(0, 0, InetAddress.getLoopbackAddress())) {
            closedPort = socket.getLocalPort();
        }
        assertThat(probe.check("http://127.0.0.1:" + closedPort + "/"))
                .isEqualTo(LivenessCheck.down("connection refused"));
    }

    @Test
    void acceptedButSilentIsDown() throws IOException {
        // Accepts the connection (backlog) but never answers: a hung service behind an open port.
        try (ServerSocket silent = new ServerSocket(0, 1, InetAddress.getLoopbackAddress())) {
            LivenessCheck check = probe.check("http://127.0.0.1:" + silent.getLocalPort() + "/");
            assertThat(check.status()).isEqualTo(LivenessStatus.DOWN);
            assertThat(check.detail()).startsWith("no HTTP response");
        }
    }

    @Test
    void unusableUrlIsUnreachable() {
        assertThat(probe.check("http://").status()).isEqualTo(LivenessStatus.UNREACHABLE);
        assertThat(probe.check("not a url").status()).isEqualTo(LivenessStatus.UNREACHABLE);
    }

    @Test
    void targetDropsFragmentAndAssumesHttp() {
        assertThat(HttpLivenessProbe.target("http://10.20.158.64:8492/frame-layout/app/#/dtlframe?url=x"))
                .hasToString("http://10.20.158.64:8492/frame-layout/app/");
        assertThat(HttpLivenessProbe.target(" 10.20.158.64:8092/frame-layout "))
                .hasToString("http://10.20.158.64:8092/frame-layout");
    }

    @Test
    void fragmentUrlIsCheckedWithoutIt() {
        assertThat(probe.check(base() + "/ok#/dashboard").status()).isEqualTo(LivenessStatus.UP);
    }
}
