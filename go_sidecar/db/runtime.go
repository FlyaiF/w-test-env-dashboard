package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"test-env-dashboard/go_sidecar/model"
	"time"

	_ "github.com/ywhking/gorm-dameng/dm8"
)

const (
	RuntimeDBOracle          = "oracle"
	RuntimeDBDameng          = "dameng"
	RuntimeDBOceanBaseOracle = "oceanbase-oracle"

	runtimeCollectTimeout = 15 * time.Second
	runtimeTestTimeout    = 10 * time.Second
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
	Type   string
	Reason string
}

func (e UnsupportedRuntimeDBTypeError) Error() string {
	if e.Reason != "" {
		return e.Reason
	}
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
	RegisterRuntimeDBAdapter(damengRuntimeAdapter{})
	RegisterRuntimeDBAdapter(oceanBaseOracleRuntimeAdapter{})
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
	case "", "0", "ora", "oracle":
		return RuntimeDBOracle
	case "dm", "dameng", "dm8":
		return RuntimeDBDameng
	case "2":
		return RuntimeDBDameng
	case "1", "ob", "ob-oracle", "oceanbase", "oceanbase-oracle", "oceanbaseoracle":
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

	ctx, cancel := context.WithTimeout(context.Background(), runtimeCollectTimeout)
	defer cancel()
	return adapter.CollectRuntimeInfo(ctx, dsn, dashboardRuntimeCredentials())
}

func TestRuntimeConnection(dbType, dsn string) error {
	adapter, ok := RuntimeDBAdapterFor(dbType)
	if !ok {
		return UnsupportedRuntimeDBTypeError{Type: NormalizeRuntimeDBType(dbType)}
	}

	ctx, cancel := context.WithTimeout(context.Background(), runtimeTestTimeout)
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
		return fresh, runtimeOperationError(ctx, "connect runtime db", err)
	}

	var systemVersion sql.NullString
	err = runtimeDB.QueryRowContext(ctx,
		"select param_value from tsys_parameter where param_code = 'SystemVersion'",
	).Scan(&systemVersion)
	if err != nil {
		return fresh, runtimeOperationError(ctx, "query SystemVersion", err)
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
		return fresh, runtimeOperationError(ctx, "query subsystem version", err)
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

type damengRuntimeAdapter struct{}

func (damengRuntimeAdapter) Type() string {
	return RuntimeDBDameng
}

func (damengRuntimeAdapter) Label() string {
	return "Dameng"
}

func (damengRuntimeAdapter) RuntimeCollectionSupported() bool {
	return true
}

func (a damengRuntimeAdapter) TestConnection(ctx context.Context, dsn string, fallback RuntimeDBCredentials) error {
	normalizedDSN, err := a.normalizeDSN(dsn, fallback)
	if err != nil {
		return err
	}

	runtimeDB, err := sql.Open("dm", normalizedDSN)
	if err != nil {
		return err
	}
	defer runtimeDB.Close()
	runtimeDB.SetMaxOpenConns(1)
	runtimeDB.SetMaxIdleConns(0)
	runtimeDB.SetConnMaxLifetime(30 * time.Second)
	return runtimeDB.PingContext(ctx)
}

func (a damengRuntimeAdapter) CollectRuntimeInfo(ctx context.Context, dsn string, fallback RuntimeDBCredentials) (model.RuntimeEnvFreshInfo, error) {
	var fresh model.RuntimeEnvFreshInfo

	normalizedDSN, err := a.normalizeDSN(dsn, fallback)
	if err != nil {
		return fresh, err
	}

	runtimeDB, err := sql.Open("dm", normalizedDSN)
	if err != nil {
		return fresh, err
	}
	defer runtimeDB.Close()
	runtimeDB.SetMaxOpenConns(1)
	runtimeDB.SetMaxIdleConns(0)
	runtimeDB.SetConnMaxLifetime(30 * time.Second)

	if err := runtimeDB.PingContext(ctx); err != nil {
		return fresh, runtimeOperationError(ctx, "connect runtime db", err)
	}

	var systemVersion sql.NullString
	err = runtimeDB.QueryRowContext(ctx,
		"select param_value from tsys_parameter where param_code = 'SystemVersion'",
	).Scan(&systemVersion)
	if err != nil {
		return fresh, runtimeOperationError(ctx, "query SystemVersion", err)
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
		return fresh, runtimeOperationError(ctx, "query subsystem version", err)
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

func (damengRuntimeAdapter) normalizeDSN(raw string, fallback RuntimeDBCredentials) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return "", fmt.Errorf("E_YWDB is empty")
	}
	lower := strings.ToLower(value)
	if strings.HasPrefix(lower, "dm://") {
		return value, nil
	}
	if strings.HasPrefix(lower, "jdbc:dm://") {
		return "dm://" + value[len("jdbc:dm://"):], nil
	}

	if match := plainCredsRe.FindStringSubmatch(value); match != nil {
		return buildDamengDSN(match[1], match[2], normalizeDamengAddress(match[3])), nil
	}

	if strings.TrimSpace(fallback.Username) == "" {
		return "", fmt.Errorf("E_YWDB has no credentials and dashboard DSN credentials are unavailable")
	}
	return buildDamengDSN(fallback.Username, fallback.Password, normalizeDamengAddress(value)), nil
}

func buildDamengDSN(username, password, address string) string {
	host, rawQuery := splitAddressQuery(address)
	u := url.URL{
		Scheme:   "dm",
		User:     url.UserPassword(strings.TrimSpace(username), strings.TrimSpace(password)),
		Host:     host,
		RawQuery: rawQuery,
	}
	return u.String()
}

func normalizeDamengAddress(address string) string {
	value := strings.TrimSpace(address)
	value = strings.TrimPrefix(value, "//")
	value = strings.TrimPrefix(value, "@")
	value = strings.TrimPrefix(value, "//")

	host, rawQuery := splitAddressQuery(value)
	host = ensureDamengPort(host)
	if rawQuery == "" {
		return host
	}
	return host + "?" + rawQuery
}

func splitAddressQuery(address string) (string, string) {
	if question := strings.Index(address, "?"); question >= 0 {
		return address[:question], address[question+1:]
	}
	return address, ""
}

func ensureDamengPort(address string) string {
	if address == "" {
		return address
	}
	if host, port, err := net.SplitHostPort(address); err == nil {
		if port == "" {
			return net.JoinHostPort(host, "5236")
		}
		return address
	}

	if strings.Contains(address, ":") {
		lastColon := strings.LastIndex(address, ":")
		if _, err := strconv.Atoi(address[lastColon+1:]); err == nil {
			return address
		}
	}
	return address + ":5236"
}

type oceanBaseOracleRuntimeAdapter struct{}

func (oceanBaseOracleRuntimeAdapter) Type() string {
	return RuntimeDBOceanBaseOracle
}

func (oceanBaseOracleRuntimeAdapter) Label() string {
	return "OceanBase Oracle"
}

func (oceanBaseOracleRuntimeAdapter) RuntimeCollectionSupported() bool {
	return true
}

func (a oceanBaseOracleRuntimeAdapter) TestConnection(ctx context.Context, dsn string, fallback RuntimeDBCredentials) error {
	normalizedDSN, err := a.normalizeDSN(dsn, fallback)
	if err != nil {
		return err
	}
	_, err = runJDBCHelper(ctx, normalizedDSN, true)
	return err
}

func (a oceanBaseOracleRuntimeAdapter) CollectRuntimeInfo(ctx context.Context, dsn string, fallback RuntimeDBCredentials) (model.RuntimeEnvFreshInfo, error) {
	var fresh model.RuntimeEnvFreshInfo
	normalizedDSN, err := a.normalizeDSN(dsn, fallback)
	if err != nil {
		return fresh, err
	}

	result, err := runJDBCHelper(ctx, normalizedDSN, false)
	if err != nil {
		return fresh, err
	}
	fresh.SystemVersion = nonEmptyStringPtr(result.SystemVersion)
	fresh.SubsystemVer = nonEmptyStringPtr(result.SubsystemVer)
	if strings.TrimSpace(result.BeginTime) != "" {
		t, err := parseJDBCTime(result.BeginTime)
		if err != nil {
			return fresh, fmt.Errorf("parse begin_time %q: %w", result.BeginTime, err)
		}
		fresh.BeginTime = &t
	}
	return fresh, nil
}

func (oceanBaseOracleRuntimeAdapter) normalizeDSN(raw string, fallback RuntimeDBCredentials) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return "", fmt.Errorf("E_YWDB is empty")
	}
	lower := strings.ToLower(value)
	if strings.HasPrefix(lower, "jdbc:oceanbase:oracle://") {
		return value, nil
	}
	if strings.HasPrefix(lower, "oceanbase:oracle://") {
		return "jdbc:" + value, nil
	}

	if match := plainCredsRe.FindStringSubmatch(value); match != nil {
		return buildOceanBaseOracleJDBCURL(match[1], match[2], normalizeOceanBaseOracleAddress(match[3])), nil
	}

	if strings.TrimSpace(fallback.Username) == "" {
		return "", fmt.Errorf("E_YWDB has no credentials and dashboard DSN credentials are unavailable")
	}
	return buildOceanBaseOracleJDBCURL(fallback.Username, fallback.Password, normalizeOceanBaseOracleAddress(value)), nil
}

func buildOceanBaseOracleJDBCURL(username, password, address string) string {
	host, service, rawQuery := splitServiceAddress(address)
	path := ""
	if service != "" {
		path = "/" + strings.TrimPrefix(service, "/")
	}
	params := splitRawQueryParams(rawQuery)
	params = setRawQueryParamDefault(params, "connectTimeout", "5000")
	params = setRawQueryParamDefault(params, "socketTimeout", "15000")
	params = setRawQueryParam(params, "user", strings.TrimSpace(username))
	params = setRawQueryParam(params, "password", strings.TrimSpace(password))
	return "jdbc:oceanbase:oracle://" + host + path + "?" + strings.Join(params, "&")
}

func splitRawQueryParams(rawQuery string) []string {
	if strings.TrimSpace(rawQuery) == "" {
		return nil
	}
	parts := strings.Split(rawQuery, "&")
	params := make([]string, 0, len(parts))
	for _, part := range parts {
		if strings.TrimSpace(part) != "" {
			params = append(params, part)
		}
	}
	return params
}

func setRawQueryParamDefault(params []string, key, value string) []string {
	if hasRawQueryParam(params, key) {
		return params
	}
	return append(params, key+"="+value)
}

func setRawQueryParam(params []string, key, value string) []string {
	prefix := key + "="
	filtered := params[:0]
	for _, param := range params {
		if !strings.EqualFold(strings.TrimSpace(strings.SplitN(param, "=", 2)[0]), key) {
			filtered = append(filtered, param)
		}
	}
	return append(filtered, prefix+value)
}

func hasRawQueryParam(params []string, key string) bool {
	for _, param := range params {
		if strings.EqualFold(strings.TrimSpace(strings.SplitN(param, "=", 2)[0]), key) {
			return true
		}
	}
	return false
}

func normalizeOceanBaseOracleAddress(address string) string {
	value := strings.TrimSpace(address)
	value = strings.TrimPrefix(value, "//")
	value = strings.TrimPrefix(value, "@")
	value = strings.TrimPrefix(value, "//")

	host, service, rawQuery := splitServiceAddress(value)
	host = ensureOceanBasePort(host)
	if rawQuery != "" {
		rawQuery = "?" + rawQuery
	}
	if service == "" {
		return host + rawQuery
	}
	return host + "/" + strings.TrimPrefix(service, "/") + rawQuery
}

func splitServiceAddress(address string) (host string, service string, rawQuery string) {
	hostAndPath, rawQuery := splitAddressQuery(address)
	if slash := strings.Index(hostAndPath, "/"); slash >= 0 {
		return hostAndPath[:slash], strings.TrimPrefix(hostAndPath[slash+1:], "/"), rawQuery
	}
	if strings.Count(hostAndPath, ":") >= 2 {
		lastColon := strings.LastIndex(hostAndPath, ":")
		if _, err := strconv.Atoi(hostAndPath[lastColon+1:]); err != nil {
			return hostAndPath[:lastColon], hostAndPath[lastColon+1:], rawQuery
		}
	}
	return hostAndPath, "", rawQuery
}

func ensureOceanBasePort(address string) string {
	if address == "" {
		return address
	}
	if host, port, err := net.SplitHostPort(address); err == nil {
		if port == "" {
			return net.JoinHostPort(host, "2881")
		}
		return address
	}
	if strings.Contains(address, ":") {
		lastColon := strings.LastIndex(address, ":")
		if _, err := strconv.Atoi(address[lastColon+1:]); err == nil {
			return address
		}
	}
	return address + ":2881"
}

type jdbcHelperResult struct {
	SystemVersion string `json:"system_version"`
	BeginTime     string `json:"begin_time"`
	SubsystemVer  string `json:"subsystem_ver"`
}

func runJDBCHelper(ctx context.Context, dsn string, testOnly bool) (jdbcHelperResult, error) {
	var result jdbcHelperResult
	helperJar, driverJar, err := resolveJDBCHelperFiles()
	if err != nil {
		return result, UnsupportedRuntimeDBTypeError{
			Type:   RuntimeDBOceanBaseOracle,
			Reason: err.Error(),
		}
	}
	javaPath, err := resolveJavaPath()
	if err != nil {
		return result, UnsupportedRuntimeDBTypeError{
			Type:   RuntimeDBOceanBaseOracle,
			Reason: "OceanBase Oracle requires java on PATH or JAVA_HOME",
		}
	}

	args := []string{
		"-cp", helperJar + string(os.PathListSeparator) + driverJar,
		"RuntimeInfoHelper",
		"--dsn", dsn,
	}
	if testOnly {
		args = append(args, "--test")
	}
	cmd := exec.CommandContext(ctx, javaPath, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return result, fmt.Errorf("run OceanBase Oracle JDBC helper: %w (output: %s)", ctxErr, strings.TrimSpace(string(output)))
		}
		return result, fmt.Errorf("run OceanBase Oracle JDBC helper: %w (output: %s)", err, strings.TrimSpace(string(output)))
	}
	if testOnly {
		return result, nil
	}
	if err := json.Unmarshal(output, &result); err != nil {
		return result, fmt.Errorf("parse OceanBase Oracle JDBC helper output: %w (output: %s)", err, strings.TrimSpace(string(output)))
	}
	return result, nil
}

func resolveJavaPath() (string, error) {
	if javaPath, err := exec.LookPath("java"); err == nil {
		return javaPath, nil
	}
	javaHome := strings.TrimSpace(os.Getenv("JAVA_HOME"))
	if javaHome != "" {
		javaPath := filepath.Join(javaHome, "bin", executableName("java"))
		if fileExists(javaPath) {
			return javaPath, nil
		}
	}
	return "", fmt.Errorf("java not found")
}

func executableName(name string) string {
	if os.PathSeparator == '\\' {
		return name + ".exe"
	}
	return name
}

func resolveJDBCHelperFiles() (helperJar string, driverJar string, err error) {
	baseDir, err := sidecarExecutableDir()
	if err != nil {
		return "", "", err
	}
	candidates := []string{
		filepath.Join(baseDir, "jdbc"),
		filepath.Join(baseDir, "..", "build", "sidecar", "jdbc"),
		filepath.Join(baseDir, "build", "sidecar", "jdbc"),
		filepath.Join(".", "build", "sidecar", "jdbc"),
	}
	for _, dir := range candidates {
		helper := filepath.Join(dir, "runtime-info-helper.jar")
		driver := filepath.Join(dir, "oceanbase-client.jar")
		if fileExists(helper) && fileExists(driver) {
			return helper, driver, nil
		}
	}
	return "", "", fmt.Errorf("OceanBase Oracle JDBC helper files are missing")
}

func sidecarExecutableDir() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(exe)
	if err != nil {
		resolved = exe
	}
	return filepath.Dir(resolved), nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func parseJDBCTime(value string) (time.Time, error) {
	value = strings.TrimSpace(value)
	layouts := []string{
		"2006-01-02 15:04:05.999999999",
		"2006-01-02 15:04:05.999999",
		"2006-01-02 15:04:05",
		time.RFC3339Nano,
		time.RFC3339,
	}
	var lastErr error
	for _, layout := range layouts {
		t, err := time.ParseInLocation(layout, value, time.Local)
		if err == nil {
			return t, nil
		}
		lastErr = err
	}
	return time.Time{}, lastErr
}

func nonEmptyStringPtr(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}

func runtimeOperationError(ctx context.Context, operation string, err error) error {
	if err == nil {
		return nil
	}
	if ctxErr := ctx.Err(); ctxErr != nil {
		return fmt.Errorf("%s: %w after %s (last error: %v)", operation, ctxErr, runtimeCollectTimeout, err)
	}
	return fmt.Errorf("%s: %w", operation, err)
}
