CREATE TABLE IF NOT EXISTS patrol_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER NOT NULL,
  session_index INTEGER NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  last_latitude REAL,
  last_longitude REAL,
  last_accuracy REAL,
  last_location_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_patrol_sessions_active
  ON patrol_sessions(department_id, status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_patrol_sessions_user
  ON patrol_sessions(user_id, started_at DESC);

CREATE TABLE IF NOT EXISTS incident_images (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id INTEGER NOT NULL,
  image_data TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (incident_id) REFERENCES incident_reports(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_incident_images_incident
  ON incident_images(incident_id, id ASC);
