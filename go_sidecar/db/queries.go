package db

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"test-env-dashboard/go_sidecar/model"
	"time"
)

var (
	jdbcWithCredsRe = regexp.MustCompile(`(?i)^jdbc:oracle:thin:([^/\s]+)/([^@\s]+)@(.+)$`)
	jdbcNoCredsRe   = regexp.MustCompile(`(?i)^jdbc:oracle:thin:@(.+)$`)
	plainCredsRe    = regexp.MustCompile(`^([^/\s]+)/([^@\s]+)@(.+)$`)
)

func scanEnv(row interface{ Scan(...any) error }) (model.EnvInfo, error) {
	var e model.EnvInfo
	var updatetime sql.NullTime
	err := row.Scan(
		&e.ENo, &e.EName, &e.EYwdb, &e.EZjdb, &e.EUrl,
		&e.EVersion, &updatetime, &e.ESeeurl, &e.EWebserveraddr,
		&e.EWeblogpath, &e.EMemo, &e.EDbtype,
	)
	if err != nil {
		return e, err
	}
	if updatetime.Valid {
		e.EUpdatetime = &updatetime.Time
	}
	return e, nil
}

const selectColumns = `E_NO, E_NAME, E_YWDB, E_ZJDB, E_URL, E_VERSION,
	E_UPDATETIME, E_SEEURL, E_WEBSERVERADDR, E_WEBLOGPATH, E_MEMO, E_DBTYPE`

func ListEnvs(search string, page, pageSize int) ([]model.EnvInfo, int, error) {
	where := ""
	var args []any
	if search != "" {
		where = ` WHERE LOWER(E_NAME) LIKE :1 OR LOWER(E_URL) LIKE :2 OR LOWER(E_MEMO) LIKE :3 OR LOWER(E_VERSION) LIKE :4`
		pat := "%" + strings.ToLower(search) + "%"
		args = append(args, pat, pat, pat, pat)
	}

	// Count total
	countSQL := "SELECT COUNT(*) FROM TENVINFO" + where
	var total int
	err := pool.QueryRow(countSQL, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count: %w", err)
	}

	// Fetch page
	offset := (page - 1) * pageSize
	dataSQL := fmt.Sprintf(
		"SELECT %s FROM TENVINFO%s ORDER BY E_NO OFFSET :o ROWS FETCH NEXT :n ROWS ONLY",
		selectColumns, where,
	)
	dataArgs := append(args, sql.Named("o", offset), sql.Named("n", pageSize))

	rows, err := pool.Query(dataSQL, dataArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("query: %w", err)
	}
	defer rows.Close()

	var list []model.EnvInfo
	for rows.Next() {
		e, err := scanEnv(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("scan: %w", err)
		}
		list = append(list, e)
	}
	return list, total, rows.Err()
}

func ListAllEnvs() ([]model.EnvInfo, error) {
	rows, err := pool.Query(fmt.Sprintf("SELECT %s FROM TENVINFO ORDER BY E_NO", selectColumns))
	if err != nil {
		return nil, fmt.Errorf("query all: %w", err)
	}
	defer rows.Close()

	var list []model.EnvInfo
	for rows.Next() {
		e, err := scanEnv(rows)
		if err != nil {
			return nil, fmt.Errorf("scan: %w", err)
		}
		list = append(list, e)
	}
	return list, rows.Err()
}

func GetEnv(id int64) (model.EnvInfo, error) {
	q := fmt.Sprintf("SELECT %s FROM TENVINFO WHERE E_NO = :1", selectColumns)
	row := pool.QueryRow(q, id)
	return scanEnv(row)
}

func CreateEnv(e model.EnvInfo) error {
	q := `INSERT INTO TENVINFO (E_NO, E_NAME, E_YWDB, E_ZJDB, E_URL, E_VERSION,
		E_UPDATETIME, E_SEEURL, E_WEBSERVERADDR, E_WEBLOGPATH, E_MEMO, E_DBTYPE)
		VALUES (:1, :2, :3, :4, :5, :6, SYSDATE, :7, :8, :9, :10, :11)`
	_, err := pool.Exec(q,
		e.ENo, e.EName, e.EYwdb, e.EZjdb, e.EUrl, e.EVersion,
		e.ESeeurl, e.EWebserveraddr, e.EWeblogpath, e.EMemo, e.EDbtype,
	)
	return err
}

func UpdateEnv(id int64, e model.EnvInfo) error {
	var setClauses []string
	var args []any
	idx := 1

	addField := func(col string, val any) {
		setClauses = append(setClauses, fmt.Sprintf("%s = :%d", col, idx))
		args = append(args, val)
		idx++
	}

	if e.EName != nil {
		addField("E_NAME", *e.EName)
	}
	if e.EYwdb != nil {
		addField("E_YWDB", *e.EYwdb)
	}
	if e.EZjdb != nil {
		addField("E_ZJDB", *e.EZjdb)
	}
	if e.EUrl != nil {
		addField("E_URL", *e.EUrl)
	}
	if e.EVersion != nil {
		addField("E_VERSION", *e.EVersion)
	}
	if e.ESeeurl != nil {
		addField("E_SEEURL", *e.ESeeurl)
	}
	if e.EWebserveraddr != nil {
		addField("E_WEBSERVERADDR", *e.EWebserveraddr)
	}
	if e.EWeblogpath != nil {
		addField("E_WEBLOGPATH", *e.EWeblogpath)
	}
	if e.EMemo != nil {
		addField("E_MEMO", *e.EMemo)
	}
	if e.EDbtype != nil {
		addField("E_DBTYPE", *e.EDbtype)
	}

	if len(setClauses) == 0 {
		return nil
	}

	// Always update timestamp
	setClauses = append(setClauses, "E_UPDATETIME = SYSDATE")

	q := fmt.Sprintf("UPDATE TENVINFO SET %s WHERE E_NO = :%d",
		strings.Join(setClauses, ", "), idx)
	args = append(args, id)

	result, err := pool.Exec(q, args...)
	if err != nil {
		return err
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func PublishCollectedEnvInfo(item model.RuntimePublishItem) error {
	if item.SystemVersion == nil && item.BeginTime == nil && item.BeginTimeText == nil {
		return nil
	}

	q, args := buildPublishCollectedSQL(item)
	if q == "" {
		return nil
	}
	log.Printf("PublishCollectedEnvInfo SQL: %s", q)
	log.Printf("PublishCollectedEnvInfo args: %s", formatSQLArgsForLog(args))
	log.Printf("PublishCollectedEnvInfo interpolated SQL: %s", interpolateSQLForLog(q, args))

	tx, err := pool.Begin()
	if err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	result, err := tx.Exec(q, args...)
	if err != nil {
		return err
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	committed = true
	return nil
}

func formatSQLArgsForLog(args []any) string {
	parts := make([]string, 0, len(args))
	for i, arg := range args {
		parts = append(parts, fmt.Sprintf(":%d=%s", i+1, formatSQLValueForLog(arg)))
	}
	return strings.Join(parts, ", ")
}

func interpolateSQLForLog(q string, args []any) string {
	out := q
	for i := len(args); i >= 1; i-- {
		out = strings.ReplaceAll(out, fmt.Sprintf(":%d", i), formatSQLValueForLog(args[i-1]))
	}
	return out
}

func formatSQLValueForLog(value any) string {
	switch v := value.(type) {
	case nil:
		return "NULL"
	case string:
		return "'" + strings.ReplaceAll(v, "'", "''") + "'"
	case time.Time:
		return "'" + v.Format("2006-01-02 15:04:05") + "'"
	default:
		return fmt.Sprintf("%v", v)
	}
}

func buildPublishCollectedSQL(item model.RuntimePublishItem) (string, []any) {
	var setClauses []string
	var args []any
	idx := 1

	if item.SystemVersion != nil {
		setClauses = append(setClauses, fmt.Sprintf("E_VERSION = :%d", idx))
		args = append(args, *item.SystemVersion)
		idx++
	}
	if item.BeginTimeText != nil {
		setClauses = append(setClauses, fmt.Sprintf("E_UPDATETIME = TO_DATE(:%d, 'YYYY-MM-DD HH24:MI:SS')", idx))
		args = append(args, *item.BeginTimeText)
		idx++
	} else if item.BeginTime != nil {
		setClauses = append(setClauses, fmt.Sprintf("E_UPDATETIME = TO_DATE(:%d, 'YYYY-MM-DD HH24:MI:SS')", idx))
		args = append(args, item.BeginTime.In(time.Local).Format("2006-01-02 15:04:05"))
		idx++
	}

	if len(setClauses) == 0 {
		return "", nil
	}

	q := fmt.Sprintf("UPDATE TENVINFO SET %s WHERE E_NO = :%d",
		strings.Join(setClauses, ", "), idx)
	args = append(args, item.ENo)
	return q, args
}

func DeleteEnv(id int64) error {
	result, err := pool.Exec("DELETE FROM TENVINFO WHERE E_NO = :1", id)
	if err != nil {
		return err
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func CollectRuntimeEnvInfo(dsn string) (model.RuntimeEnvFreshInfo, error) {
	var fresh model.RuntimeEnvFreshInfo
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	normalizedDSN, err := normalizeOracleDSN(dsn)
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

func normalizeOracleDSN(raw string) (string, error) {
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
	username, password, ok := dashboardCredentials()
	if !ok {
		return "", fmt.Errorf("E_YWDB has no credentials and dashboard DSN credentials are unavailable")
	}
	return buildOracleDSN(username, password, normalizeOracleAddress(address)), nil
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

func BuildRuntimeCollectionResult(env model.EnvInfo, fresh model.RuntimeEnvFreshInfo, collectedAt time.Time) model.RuntimeEnvCollectionResult {
	diff := model.RuntimeEnvDiff{
		VersionChanged:    !sameString(env.EVersion, fresh.SystemVersion),
		UpdateTimeChanged: !sameTimeSecond(env.EUpdatetime, fresh.BeginTime),
	}
	status := "unchanged"
	if diff.VersionChanged || diff.UpdateTimeChanged {
		status = "changed"
	}
	return model.RuntimeEnvCollectionResult{
		ENo:         env.ENo,
		EName:       env.EName,
		Status:      status,
		Current:     env,
		Fresh:       &fresh,
		Diff:        diff,
		CollectedAt: collectedAt,
	}
}

func BuildRuntimeSkippedResult(env model.EnvInfo, reason string, collectedAt time.Time) model.RuntimeEnvCollectionResult {
	return model.RuntimeEnvCollectionResult{
		ENo:         env.ENo,
		EName:       env.EName,
		Status:      "skipped",
		Current:     env,
		Error:       reason,
		CollectedAt: collectedAt,
	}
}

func BuildRuntimeFailedResult(env model.EnvInfo, err error, collectedAt time.Time) model.RuntimeEnvCollectionResult {
	return model.RuntimeEnvCollectionResult{
		ENo:         env.ENo,
		EName:       env.EName,
		Status:      "failed",
		Current:     env,
		Error:       err.Error(),
		CollectedAt: collectedAt,
	}
}

func sameString(a, b *string) bool {
	var av, bv string
	if a != nil {
		av = strings.TrimSpace(*a)
	}
	if b != nil {
		bv = strings.TrimSpace(*b)
	}
	return av == bv
}

func sameTimeSecond(a, b *time.Time) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return a.UTC().Truncate(time.Second).Equal(b.UTC().Truncate(time.Second))
}

func Now() time.Time {
	return time.Now()
}
