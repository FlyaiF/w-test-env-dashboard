package com.flyaif.envdashboard.access;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/** Wiring for the Access Brokering context: binds {@link AccessProperties} from configuration. */
@Configuration
@EnableConfigurationProperties(AccessProperties.class)
public class AccessConfig {
}
