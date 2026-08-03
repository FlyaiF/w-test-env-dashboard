package com.flyaif.envdashboard.clientupdate;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Finds the newest publishable env_viewer build in the operator-managed updates directory.
 *
 * <p>The directory is the whole publishing contract (ADR: update feature): the operator drops
 * {@code env_viewer-<version>-<platform>.zip} (and optionally {@code env_viewer-<version>.notes.md})
 * and this service serves whatever the highest version per platform is. The directory is rescanned
 * on every request — it holds a handful of files — but SHA-256 digests are cached per (path, mtime,
 * size) so each zip is hashed once, not per poll.
 */
@Service
public class ClientUpdateService {

    private static final Logger log = LoggerFactory.getLogger(ClientUpdateService.class);

    private static final Pattern ZIP_NAME =
            Pattern.compile("env_viewer-(\\d+\\.\\d+\\.\\d+)-(windows|macos)\\.zip");

    private final ClientUpdateProperties properties;
    private final Map<Path, Digest> digestCache = new ConcurrentHashMap<>();

    private record Digest(long lastModifiedMillis, long sizeBytes, String sha256) {}

    public ClientUpdateService(ClientUpdateProperties properties) {
        this.properties = properties;
    }

    /** The newest release for {@code platform}, or empty when disabled/none published. */
    public Optional<ClientRelease> latest(String platform) {
        Path dir = updatesDir();
        if (dir == null) {
            return Optional.empty();
        }
        try (Stream<Path> files = Files.list(dir)) {
            return files.map(p -> parse(p, platform))
                    .filter(Optional::isPresent)
                    .map(Optional::get)
                    .max(Comparator.comparing(Parsed::version, ClientUpdateService::compareVersions))
                    .map(this::toRelease);
        } catch (IOException e) {
            log.warn("Cannot scan client-updates dir {}: {}", dir, e.toString());
            return Optional.empty();
        }
    }

    /** The exact release a client asked to download; empty if it has been replaced/removed. */
    public Optional<ClientRelease> find(String platform, String version) {
        Path dir = updatesDir();
        if (dir == null) {
            return Optional.empty();
        }
        Path zip = dir.resolve("env_viewer-" + version + "-" + platform + ".zip");
        if (!ZIP_NAME.matcher(zip.getFileName().toString()).matches() || !Files.isRegularFile(zip)) {
            return Optional.empty();
        }
        return Optional.of(toRelease(new Parsed(version, platform, zip)));
    }

    private Path updatesDir() {
        String dir = properties.getDir();
        if (dir == null || dir.isBlank()) {
            return null;
        }
        Path path = Path.of(dir);
        if (!Files.isDirectory(path)) {
            log.warn("client-updates dir {} does not exist; serving no updates", path);
            return null;
        }
        return path;
    }

    private record Parsed(String version, String platform, Path zip) {}

    private static Optional<Parsed> parse(Path file, String platform) {
        Matcher m = ZIP_NAME.matcher(file.getFileName().toString());
        if (!m.matches() || !m.group(2).equals(platform) || !Files.isRegularFile(file)) {
            return Optional.empty();
        }
        return Optional.of(new Parsed(m.group(1), platform, file));
    }

    private ClientRelease toRelease(Parsed parsed) {
        try {
            long size = Files.size(parsed.zip());
            return new ClientRelease(
                    parsed.version(),
                    parsed.platform(),
                    parsed.zip(),
                    size,
                    sha256(parsed.zip(), size),
                    readNotes(parsed));
        } catch (IOException e) {
            throw new java.io.UncheckedIOException(e);
        }
    }

    private String readNotes(Parsed parsed) throws IOException {
        Path notes = parsed.zip().resolveSibling("env_viewer-" + parsed.version() + ".notes.md");
        return Files.isRegularFile(notes) ? Files.readString(notes, StandardCharsets.UTF_8) : null;
    }

    private String sha256(Path zip, long size) throws IOException {
        long mtime = Files.getLastModifiedTime(zip).toMillis();
        Digest cached = digestCache.get(zip);
        if (cached != null && cached.lastModifiedMillis() == mtime && cached.sizeBytes() == size) {
            return cached.sha256();
        }
        MessageDigest digest;
        try {
            digest = MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
        try (InputStream in = Files.newInputStream(zip)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) >= 0) {
                digest.update(buffer, 0, read);
            }
        }
        String sha = HexFormat.of().formatHex(digest.digest());
        digestCache.put(zip, new Digest(mtime, size, sha));
        return sha;
    }

    /** Numeric x.y.z comparison; the zip-name pattern guarantees the shape. */
    static int compareVersions(String a, String b) {
        String[] as = a.split("\\.");
        String[] bs = b.split("\\.");
        for (int i = 0; i < 3; i++) {
            int cmp = Integer.compare(Integer.parseInt(as[i]), Integer.parseInt(bs[i]));
            if (cmp != 0) {
                return cmp;
            }
        }
        return 0;
    }
}
