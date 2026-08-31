-- Link the existing Pentadbiran PKK 4 presentation scans to the same
-- patrol-session structure used by Admin > Sejarah Rondaan.
-- No report data is duplicated: patrol_session_history references the exact
-- DEMO-PKK4-202608-* client_session_id values already stored on nfc_scans.

DELETE FROM patrol_session_history
WHERE client_session_id LIKE 'DEMO-PKK4-202608-%';

WITH demo_sessions AS (
  SELECT
    s.user_id,
    s.client_session_id,
    MIN(s.scanned_at) AS first_scan,
    MAX(s.scanned_at) AS last_scan
  FROM nfc_scans s
  WHERE s.client_event_id LIKE 'DEMO-PKK4-202608-%'
    AND s.client_session_id IS NOT NULL
  GROUP BY s.user_id, s.client_session_id
)
INSERT INTO patrol_session_history (
  user_id,
  department_id,
  client_session_id,
  started_at,
  ended_at,
  created_at,
  updated_at
)
SELECT
  ds.user_id,
  u.department_id,
  ds.client_session_id,
  strftime('%Y-%m-%dT%H:%M:%SZ', datetime(ds.first_scan, '-5 minutes')),
  strftime('%Y-%m-%dT%H:%M:%SZ', datetime(ds.last_scan, '+10 minutes')),
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM demo_sessions ds
JOIN users u ON u.id = ds.user_id;
