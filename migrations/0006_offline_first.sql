CREATE TABLE IF NOT EXISTS offline_event_receipts (
  client_event_id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  synced_at TEXT NOT NULL,
  result_json TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_offline_receipts_user_time
  ON offline_event_receipts(user_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS field_event_locations (
  client_event_id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracy REAL,
  recorded_at TEXT NOT NULL,
  FOREIGN KEY (client_event_id) REFERENCES offline_event_receipts(client_event_id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS patrol_activity_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_event_id TEXT NOT NULL UNIQUE,
  client_session_id TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  event_type TEXT NOT NULL CHECK (event_type IN ('start', 'end')),
  occurred_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_patrol_activity_user_time
  ON patrol_activity_log(user_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS welfare_checks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_event_id TEXT NOT NULL UNIQUE,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  status TEXT NOT NULL DEFAULT 'ok',
  note TEXT,
  checked_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_welfare_checks_time
  ON welfare_checks(checked_at DESC);

CREATE TABLE IF NOT EXISTS live_patrol_presence (
  user_id INTEGER PRIMARY KEY,
  department_id INTEGER,
  client_session_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  last_latitude REAL,
  last_longitude REAL,
  last_accuracy REAL,
  last_location_at TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_live_presence_active
  ON live_patrol_presence(active, updated_at DESC);

CREATE TABLE IF NOT EXISTS live_patrol_trail (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  client_session_id TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracy REAL,
  recorded_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_live_trail_user_time
  ON live_patrol_trail(user_id, recorded_at DESC);
