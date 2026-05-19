package db

import (
	"database/sql"
	"fmt"
	"log"
	"strings"
	"test-env-dashboard/go_sidecar/model"
	"time"
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

func (OracleConfigRepository) ListEnvs(search string, page, pageSize int) ([]model.EnvInfo, int, error) {
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

func (OracleConfigRepository) ListAllEnvs() ([]model.EnvInfo, error) {
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

func (OracleConfigRepository) GetEnv(id int64) (model.EnvInfo, error) {
	q := fmt.Sprintf("SELECT %s FROM TENVINFO WHERE E_NO = :1", selectColumns)
	row := pool.QueryRow(q, id)
	return scanEnv(row)
}

func (OracleConfigRepository) CreateEnv(e model.EnvInfo) error {
	q := `INSERT INTO TENVINFO (E_NO, E_NAME, E_YWDB, E_ZJDB, E_URL, E_VERSION,
		E_UPDATETIME, E_SEEURL, E_WEBSERVERADDR, E_WEBLOGPATH, E_MEMO, E_DBTYPE)
		VALUES (:1, :2, :3, :4, :5, :6, SYSDATE, :7, :8, :9, :10, :11)`
	_, err := pool.Exec(q,
		e.ENo, e.EName, e.EYwdb, e.EZjdb, e.EUrl, e.EVersion,
		e.ESeeurl, e.EWebserveraddr, e.EWeblogpath, e.EMemo, e.EDbtype,
	)
	return err
}

func (OracleConfigRepository) UpdateEnv(id int64, e model.EnvInfo) error {
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

func (OracleConfigRepository) PublishCollectedEnvInfo(item model.RuntimePublishItem) error {
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

func (OracleConfigRepository) DeleteEnv(id int64) error {
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
		DbType:      NormalizeRuntimeDBType(pointerValue(env.EDbtype)),
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
		DbType:      NormalizeRuntimeDBType(pointerValue(env.EDbtype)),
		Current:     env,
		Error:       reason,
		CollectedAt: collectedAt,
	}
}

func BuildRuntimeUnsupportedResult(env model.EnvInfo, reason string, collectedAt time.Time) model.RuntimeEnvCollectionResult {
	return model.RuntimeEnvCollectionResult{
		ENo:         env.ENo,
		EName:       env.EName,
		Status:      "unsupported",
		DbType:      NormalizeRuntimeDBType(pointerValue(env.EDbtype)),
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
		DbType:      NormalizeRuntimeDBType(pointerValue(env.EDbtype)),
		Current:     env,
		Error:       err.Error(),
		CollectedAt: collectedAt,
	}
}

func pointerValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
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
