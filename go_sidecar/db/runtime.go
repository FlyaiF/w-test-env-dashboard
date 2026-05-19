package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"test-env-dashboard/go_sidecar/model"
	"time"
)

const (
	RuntimeDBOracle          = "oracle"
	RuntimeDBDameng          = "dameng"
	RuntimeDBOceanBaseOracle = "oceanbase-oracle"
)

type RuntimeDBCredentials struct {
	Username string
	Password string
}

type RuntimeDBAdapter interface {
	Type() string
	Label() string
	RuntimeCollectionSupported() bool
	TestConnection(ctx context.Context, dsn string, fallback RuntimeDBCredentials) error
	CollectRuntimeInfo(ctx context.Context, dsn string, fallback RuntimeDBCredentials) (model.RuntimeEnvFreshInfo, error)
}

type UnsupportedRuntimeDBTypeError struct {
	Type string
}

func (e UnsupportedRuntimeDBTypeError) Error() string {
	if e.Type == "" {
		return "runtime database type is empty"
	}
	return fmt.Sprintf("runtime database type %q is not supported yet", e.Type)
}

var runtimeDBAdapters = map[string]RuntimeDBAdapter{}
var runtimeDBTypeLabels = map[string]string{
	RuntimeDBOracle:          "Oracle",
	RuntimeDBDameng:          "Dameng",
	RuntimeDBOceanBaseOracle: "OceanBase Oracle",
}

func init() {
	RegisterRuntimeDBAdapter(oracleRuntimeAdapter{})
}

func RegisterRuntimeDBAdapter(adapter RuntimeDBAdapter) {
	runtimeDBAdapters[adapter.Type()] = adapter
	runtimeDBTypeLabels[adapter.Type()] = adapter.Label()
}

func RuntimeDBTypes() []model.DBTypeInfo {
	keys := make([]string, 0, len(runtimeDBTypeLabels))
	for key := range runtimeDBTypeLabels {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	types := make([]model.DBTypeInfo, 0, len(keys))
	for _, key := range keys {
		adapter, ok := runtimeDBAdapters[key]
		types = append(types, model.DBTypeInfo{
			Type:                       key,
			Label:                      runtimeDBTypeLabels[key],
			RuntimeCollectionSupported: ok && adapter.RuntimeCollectionSupported(),
		})
	}
	return types
}

func RuntimeDBAdapterFor(dbType string) (RuntimeDBAdapter, bool) {
	adapter, ok := runtimeDBAdapters[NormalizeRuntimeDBType(dbType)]
	return adapter, ok
}

func NormalizeRuntimeDBType(dbType string) string {
	value := strings.ToLower(strings.TrimSpace(dbType))
	value = strings.ReplaceAll(value, "_", "-")
	value = strings.ReplaceAll(value, " ", "-")
	switch value {
	case "", "ora", "oracle":
		return RuntimeDBOracle
	case "dm", "dameng", "dm8":
		return RuntimeDBDameng
	case "ob", "ob-oracle", "oceanbase", "oceanbase-oracle", "oceanbaseoracle":
		return RuntimeDBOceanBaseOracle
	default:
		return value
	}
}

func CollectRuntimeEnvInfo(dbType, dsn string) (model.RuntimeEnvFreshInfo, error) {
	adapter, ok := RuntimeDBAdapterFor(dbType)
	if !ok {
		return model.RuntimeEnvFreshInfo{}, UnsupportedRuntimeDBTypeError{Type: NormalizeRuntimeDBType(dbType)}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return adapter.CollectRuntimeInfo(ctx, dsn, dashboardRuntimeCredentials())
}

func TestRuntimeConnection(dbType, dsn string) error {
	adapter, ok := RuntimeDBAdapterFor(dbType)
	if !ok {
		return UnsupportedRuntimeDBTypeError{Type: NormalizeRuntimeDBType(dbType)}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return adapter.TestConnection(ctx, dsn, dashboardRuntimeCredentials())
}

func dashboardRuntimeCredentials() RuntimeDBCredentials {
	username, password, ok := dashboardCredentials()
	if !ok {
		return RuntimeDBCredentials{}
	}
	return RuntimeDBCredentials{Username: username, Password: password}
}

type oracleRuntimeAdapter struct{}

func (oracleRuntimeAdapter) Type() string {
	return RuntimeDBOracle
}

func (oracleRuntimeAdapter) Label() string {
	return "Oracle"
}

func (oracleRuntimeAdapter) RuntimeCollectionSupported() bool {
	return true
}

func (a oracleRuntimeAdapter) TestConnection(ctx context.Context, dsn string, fallback RuntimeDBCredentials) error {
	normalizedDSN, err := a.normalizeDSN(dsn, fallback)
	if err != nil {
		return err
	}

	runtimeDB, err := sql.Open("oracle", normalizedDSN)
	if err != nil {
		return err
	}
	defer runtimeDB.Close()
	runtimeDB.SetMaxOpenConns(1)
	runtimeDB.SetMaxIdleConns(0)
	runtimeDB.SetConnMaxLifetime(30 * time.Second)
	return runtimeDB.PingContext(ctx)
}

func (a oracleRuntimeAdapter) CollectRuntimeInfo(ctx context.Context, dsn string, fallback RuntimeDBCredentials) (model.RuntimeEnvFreshInfo, error) {
	var fresh model.RuntimeEnvFreshInfo

	normalizedDSN, err := a.normalizeDSN(dsn, fallback)
	if err != nil {
		return fresh, err
	}

	runtimeDB, err := sql.Open("oracle", normalizedDSN)
	if err != nil {
		return fresh, err
	}
	defer runtimeDB.Close()
	runtimeDB.SetMaxOpenConns(1)
	runtimeDB.SetMaxIdleConns(0)
	runtimeDB.SetConnMaxLifetime(30 * time.Second)

	if err := runtimeDB.PingContext(ctx); err != nil {
		return fresh, fmt.Errorf("connect runtime db: %w", err)
	}

	var systemVersion sql.NullString
	err = runtimeDB.QueryRowContext(ctx,
		"select param_value from tsys_parameter where param_code = 'SystemVersion'",
	).Scan(&systemVersion)
	if err != nil {
		return fresh, fmt.Errorf("query SystemVersion: %w", err)
	}
	if systemVersion.Valid {
		v := strings.TrimSpace(systemVersion.String)
		if v != "" {
			fresh.SystemVersion = &v
		}
	}

	var beginTime sql.NullTime
	var subsystemVer sql.NullString
	err = runtimeDB.QueryRowContext(ctx,
		"select * from (select begin_time, subsystem_ver from jres_subsystem_rc order by begin_time desc) where rownum = 1",
	).Scan(&beginTime, &subsystemVer)
	if err != nil {
		return fresh, fmt.Errorf("query subsystem version: %w", err)
	}
	if beginTime.Valid {
		t := beginTime.Time
		fresh.BeginTime = &t
	}
	if subsystemVer.Valid {
		v := strings.TrimSpace(subsystemVer.String)
		if v != "" {
			fresh.SubsystemVer = &v
		}
	}

	return fresh, nil
}

var (
	jdbcWithCredsRe = regexp.MustCompile(`(?i)^jdbc:oracle:thin:([^/\s]+)/([^@\s]+)@(.+)$`)
	jdbcNoCredsRe   = regexp.MustCompile(`(?i)^jdbc:oracle:thin:@(.+)$`)
	plainCredsRe    = regexp.MustCompile(`^([^/\s]+)/([^@\s]+)@(.+)$`)
)

func (oracleRuntimeAdapter) normalizeDSN(raw string, fallback RuntimeDBCredentials) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return "", fmt.Errorf("E_YWDB is empty")
	}
	if strings.HasPrefix(strings.ToLower(value), "oracle://") {
		return value, nil
	}

	if match := jdbcWithCredsRe.FindStringSubmatch(value); match != nil {
		return buildOracleDSN(match[1], match[2], normalizeOracleAddress(match[3])), nil
	}
	if match := plainCredsRe.FindStringSubmatch(value); match != nil {
		return buildOracleDSN(match[1], match[2], normalizeOracleAddress(match[3])), nil
	}

	address := value
	if match := jdbcNoCredsRe.FindStringSubmatch(value); match != nil {
		address = match[1]
	}
	if strings.TrimSpace(fallback.Username) == "" {
		return "", fmt.Errorf("E_YWDB has no credentials and dashboard DSN credentials are unavailable")
	}
	return buildOracleDSN(fallback.Username, fallback.Password, normalizeOracleAddress(address)), nil
}

func normalizeOracleDSN(raw string) (string, error) {
	return oracleRuntimeAdapter{}.normalizeDSN(raw, dashboardRuntimeCredentials())
}

func normalizeOracleAddress(address string) string {
	value := strings.TrimSpace(address)
	value = strings.TrimPrefix(value, "//")
	value = strings.TrimPrefix(value, "@")
	value = strings.TrimPrefix(value, "//")
	if strings.Count(value, ":") >= 2 && !strings.Contains(value, "/") {
		lastColon := strings.LastIndex(value, ":")
		value = value[:lastColon] + "/" + value[lastColon+1:]
	}
	value = ensureOraclePort(value)
	return value
}

func buildOracleDSN(username, password, address string) string {
	u := url.URL{
		Scheme: "oracle",
		User:   url.UserPassword(strings.TrimSpace(username), strings.TrimSpace(password)),
		Host:   address,
	}
	if slash := strings.Index(address, "/"); slash >= 0 {
		u.Host = address[:slash]
		u.Path = "/" + strings.TrimPrefix(address[slash+1:], "/")
	}
	return u.String()
}

func ensureOraclePort(address string) string {
	hostPart := address
	servicePart := ""
	if slash := strings.Index(address, "/"); slash >= 0 {
		hostPart = address[:slash]
		servicePart = address[slash:]
	}

	if hostPart == "" {
		return address
	}
	if host, port, err := net.SplitHostPort(hostPart); err == nil {
		if port == "" {
			return net.JoinHostPort(host, "1521") + servicePart
		}
		return hostPart + servicePart
	}

	// IPv6 literals without brackets are out of scope for legacy config values.
	if strings.Contains(hostPart, ":") {
		lastColon := strings.LastIndex(hostPart, ":")
		if _, err := strconv.Atoi(hostPart[lastColon+1:]); err == nil {
			return hostPart + servicePart
		}
	}
	return hostPart + ":1521" + servicePart
}

func IsUnsupportedRuntimeDBType(err error) bool {
	var target UnsupportedRuntimeDBTypeError
	return errors.As(err, &target)
}
