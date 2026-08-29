CREATE TABLE IF NOT EXISTS patrol_session_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  client_session_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, client_session_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_patrol_session_history_department_time
  ON patrol_session_history(department_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_patrol_session_history_user_time
  ON patrol_session_history(user_id, started_at DESC);

INSERT OR IGNORE INTO patrol_session_history
  (user_id, department_id, client_session_id, started_at, ended_at, updated_at)
SELECT
  user_id,
  MAX(department_id),
  client_session_id,
  MIN(CASE WHEN event_type = 'start' THEN occurred_at END),
  MAX(CASE WHEN event_type = 'end' THEN occurred_at END),
  CURRENT_TIMESTAMP
FROM patrol_activity_log
GROUP BY user_id, client_session_id
HAVING MIN(CASE WHEN event_type = 'start' THEN occurred_at END) IS NOT NULL;

INSERT OR IGNORE INTO patrol_session_history
  (user_id, department_id, client_session_id, started_at, ended_at, updated_at)
SELECT user_id, department_id, client_session_id, started_at, ended_at, updated_at
FROM live_patrol_presence
WHERE started_at IS NOT NULL;
