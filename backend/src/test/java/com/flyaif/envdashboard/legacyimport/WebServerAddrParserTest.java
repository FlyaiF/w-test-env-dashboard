package com.flyaif.envdashboard.legacyimport;

import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

class WebServerAddrParserTest {

    @Test
    void parsesFullCompositeString() {
        WebServerAddr addr = WebServerAddrParser.parse("10.0.1.10:8080&deploy/s3cr3t").orElseThrow();

        assertThat(addr.host()).isEqualTo("10.0.1.10");
        assertThat(addr.port()).isEqualTo(8080);
        assertThat(addr.username()).isEqualTo("deploy");
        assertThat(addr.password()).isEqualTo("s3cr3t");
    }

    @Test
    void parsesAddressWithoutCredentials() {
        WebServerAddr addr = WebServerAddrParser.parse("host.test:22").orElseThrow();

        assertThat(addr.host()).isEqualTo("host.test");
        assertThat(addr.port()).isEqualTo(22);
        assertThat(addr.username()).isNull();
        assertThat(addr.password()).isNull();
    }

    @Test
    void blanksNonNumericPortButKeepsHost() {
        WebServerAddr addr = WebServerAddrParser.parse("host.test:notaport&u/p").orElseThrow();

        assertThat(addr.host()).isEqualTo("host.test");
        assertThat(addr.port()).isNull();
        assertThat(addr.username()).isEqualTo("u");
        assertThat(addr.password()).isEqualTo("p");
    }

    @Test
    void keepsUsernameWhenPasswordMissing() {
        WebServerAddr addr = WebServerAddrParser.parse("host.test:22&onlyuser").orElseThrow();

        assertThat(addr.username()).isEqualTo("onlyuser");
        assertThat(addr.password()).isNull();
    }

    @Test
    void hostOnlyIsUsable() {
        WebServerAddr addr = WebServerAddrParser.parse("host.test").orElseThrow();

        assertThat(addr.host()).isEqualTo("host.test");
        assertThat(addr.port()).isNull();
    }

    @Test
    void blankOrNullIsEmpty() {
        assertThat(WebServerAddrParser.parse(null)).isEmpty();
        assertThat(WebServerAddrParser.parse("   ")).isEmpty();
    }

    @Test
    void noHostIsEmpty() {
        // Leading ':' means there is no host to anchor a Server on.
        Optional<WebServerAddr> parsed = WebServerAddrParser.parse(":8080&u/p");
        assertThat(parsed).isEmpty();
    }
}
