ALTER TABLE nfc_scans ADD COLUMN client_session_id TEXT;

UPDATE nfc_scans AS scan
SET client_session_id = (
  SELECT history.client_session_id
  FROM patrol_session_history AS history
  WHERE history.user_id = scan.user_id
    AND scan.scanned_at >= history.started_at
    AND (history.ended_at IS NULL OR scan.scanned_at <= history.ended_at)
  ORDER BY history.started_at DESC
  LIMIT 1
)
WHERE client_session_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_nfc_scans_patrol_session
  ON nfc_scans(user_id, client_session_id, scanned_at);
