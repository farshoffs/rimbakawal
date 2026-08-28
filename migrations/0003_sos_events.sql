CREATE TABLE IF NOT EXISTS sos_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  triggered_at TEXT NOT NULL,
  note TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_sos_events_time ON sos_events(triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_events_user_time ON sos_events(user_id, triggered_at DESC);
