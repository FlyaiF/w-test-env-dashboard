-- Persist the probe's failure explanation so the client can show 采集失败：<detail>.
-- Null whenever the last collection succeeded (OK); set for FAILED/UNSUPPORTED.
ALTER TABLE component ADD collection_detail VARCHAR2(2000);
