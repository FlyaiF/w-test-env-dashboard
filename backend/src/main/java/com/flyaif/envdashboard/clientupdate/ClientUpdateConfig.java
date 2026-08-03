package com.flyaif.envdashboard.clientupdate;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties(ClientUpdateProperties.class)
public class ClientUpdateConfig {}
