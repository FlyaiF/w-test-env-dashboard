package com.flyaif.envdashboard.collection.liveness;

import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.net.ConnectException;
import java.net.NoRouteToHostException;
import java.net.URI;
import java.net.UnknownHostException;
import java.net.http.HttpClient;
import java.net.http.HttpConnectTimeoutException;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.channels.UnresolvedAddressException;
import java.time.Duration;
import java.util.Locale;

/**
 * {@link LivenessProbe} over plain HTTP GET. A Component's URL is usually its nginx entry point, so
 * one request exercises gateway, UI and main service together:
 *
 * <ul>
 *   <li>any status below 500 is {@code UP} — redirects are not followed, so a 302 to a login or CAS
 *       page still counts as serving;</li>
 *   <li>5xx is {@code DOWN} — typically nginx answering 502 because the service behind it is gone;</li>
 *   <li>connection refused or no response within the request timeout is {@code DOWN};</li>
 *   <li>connect timeout, no route, unknown host or an unusable URL is {@code UNREACHABLE}.</li>
 * </ul>
 *
 * The body is never read: the stream is closed as soon as headers arrive, so a large or streaming
 * page cannot hold the check open.
 */
@Component
public class HttpLivenessProbe implements LivenessProbe {

    private final HttpClient http;
    private final Duration requestTimeout;

    public HttpLivenessProbe(LivenessProperties properties) {
        this.http = HttpClient.newBuilder()
                .connectTimeout(properties.getConnectTimeout())
                .followRedirects(HttpClient.Redirect.NEVER)
                .build();
        this.requestTimeout = properties.getRequestTimeout();
    }

    @Override
    public LivenessCheck check(String url) {
        URI uri;
        try {
            uri = target(url);
        } catch (IllegalArgumentException e) {
            return LivenessCheck.unreachable("invalid URL: " + url);
        }
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(requestTimeout)
                .GET()
                .build();
        try {
            HttpResponse<InputStream> response = http.send(request, HttpResponse.BodyHandlers.ofInputStream());
            response.body().close();
            int status = response.statusCode();
            return status >= 500
                    ? LivenessCheck.down("HTTP " + status)
                    : LivenessCheck.up("HTTP " + status);
        } catch (HttpConnectTimeoutException e) {
            return LivenessCheck.unreachable("connect timed out");
        } catch (HttpTimeoutException e) {
            return LivenessCheck.down("no HTTP response within " + requestTimeout.toSeconds() + "s");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return LivenessCheck.unreachable("check interrupted");
        } catch (IOException e) {
            return classify(e);
        } catch (RuntimeException e) {
            return LivenessCheck.unreachable(describe(e));
        }
    }

    /** The URL as a request target: {@code http://} assumed when no scheme, fragment dropped. */
    static URI target(String url) {
        String trimmed = url.strip();
        int hash = trimmed.indexOf('#');
        if (hash >= 0) {
            trimmed = trimmed.substring(0, hash);
        }
        if (!trimmed.contains("://")) {
            trimmed = "http://" + trimmed;
        }
        URI uri = URI.create(trimmed);
        if (uri.getHost() == null) {
            throw new IllegalArgumentException("no host in " + url);
        }
        return uri;
    }

    /**
     * The JDK client wraps socket errors in message-less {@code ConnectException}s (JDK 21: a refused
     * connection is {@code ConnectException -> ConnectException -> ClosedChannelException}), so walk
     * the cause chain: rule out the host-level failures first, then any remaining connect failure is
     * a refusal — the host is up but nothing listens on the port.
     */
    private static LivenessCheck classify(IOException e) {
        boolean connectFailure = false;
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof UnresolvedAddressException || t instanceof UnknownHostException) {
                return LivenessCheck.unreachable("unknown host");
            }
            String message = t.getMessage() == null ? "" : t.getMessage().toLowerCase(Locale.ROOT);
            if (t instanceof NoRouteToHostException || message.contains("no route")
                    || message.contains("unreachable")) {
                return LivenessCheck.unreachable("no route to host");
            }
            connectFailure |= t instanceof ConnectException;
        }
        return connectFailure
                ? LivenessCheck.down("connection refused")
                : LivenessCheck.unreachable(describe(e));
    }

    private static String describe(Throwable e) {
        Throwable root = e;
        while (root.getCause() != null && root.getMessage() == null) {
            root = root.getCause();
        }
        String message = root.getMessage();
        return root.getClass().getSimpleName() + (message == null ? "" : ": " + message);
    }
}
