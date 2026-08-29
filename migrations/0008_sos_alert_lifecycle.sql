ALTER TABLE sos_events ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE sos_events ADD COLUMN resolved_at TEXT;
ALTER TABLE sos_events ADD COLUMN resolved_by_user_id INTEGER;
ALTER TABLE sos_events ADD COLUMN resolution_note TEXT;

CREATE TABLE IF NOT EXISTS sos_alert_receipts (
  sos_event_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  acknowledged_at TEXT NOT NULL,
  PRIMARY KEY (sos_event_id, user_id),
  FOREIGN KEY (sos_event_id) REFERENCES sos_events(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sos_events_department_status_time
  ON sos_events(department_id, status, triggered_at DESC);

CREATE INDEX IF NOT EXISTS idx_sos_alert_receipts_user
  ON sos_alert_receipts(user_id, acknowledged_at DESC);
