package com.flyaif.envdashboard.legacyimport;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.jdbc.DataSourceBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;

/**
 * Entry point for the one-time {@code TENVINFO} import, active only under the {@code import} profile so
 * it never fires during normal boot or tests (ADR-0004, PRD §8). Reads the legacy rows, runs the
 * {@link TenvinfoImporter}, logs the {@link ImportReport}, and exits — the tool is run-once, not a
 * long-lived service. Dry-run by default (see {@link ImportProperties}); pass
 * {@code --envdashboard.import.dry-run=false} to actually write.
 */
@Component
@Profile("import")
@EnableConfigurationProperties(ImportProperties.class)
public class TenvinfoImportRunner implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(TenvinfoImportRunner.class);

    private final TenvinfoImporter importer;
    private final ImportProperties properties;
    private final ConfigurableApplicationContext context;

    public TenvinfoImportRunner(TenvinfoImporter importer,
                                ImportProperties properties,
                                ConfigurableApplicationContext context) {
        this.importer = importer;
        this.properties = properties;
        this.context = context;
    }

    @Override
    public void run(String... args) {
        ImportProperties.Legacy legacy = properties.getLegacy();
        if (legacy.getUrl() == null || legacy.getUrl().isBlank()) {
            log.error("envdashboard.import.legacy.url is not set — nothing to import. "
                    + "Provide the legacy database coordinates and re-run.");
            exit(2);
            return;
        }

        DataSource legacyDataSource = DataSourceBuilder.create()
                .url(legacy.getUrl())
                .username(legacy.getUsername())
                .password(legacy.getPassword())
                .build();

        LegacyEnvSource source = new JdbcLegacyEnvSource(legacyDataSource, properties.getTable());

        log.info("Starting TENVINFO import from {} (table {}), dryRun={}",
                legacy.getUrl(), properties.getTable(), properties.isDryRun());
        try {
            ImportReport report = importer.run(source, properties.isDryRun());
            log.info("\n{}", report.render());
        } catch (RuntimeException e) {
            log.error("TENVINFO import failed: {}", e.getMessage(), e);
            exit(1);
            return;
        }

        exit(0);
    }

    private void exit(int code) {
        System.exit(SpringApplication.exit(context, () -> code));
    }
}
