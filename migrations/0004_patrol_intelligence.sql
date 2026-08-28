ALTER TABLE departments ADD COLUMN route_order_enforced INTEGER NOT NULL DEFAULT 1 CHECK (route_order_enforced IN (0, 1));
ALTER TABLE checkpoints ADD COLUMN job_instruction TEXT;

CREATE TABLE IF NOT EXISTS incident_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  checkpoint_id INTEGER,
  category TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'normal',
  note TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TEXT NOT NULL,
  acknowledged_at TEXT,
  resolved_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL,
  FOREIGN KEY (checkpoint_id) REFERENCES checkpoints(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_incident_status_time ON incident_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incident_department ON incident_reports(department_id, created_at DESC);
