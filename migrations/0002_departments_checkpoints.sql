CREATE TABLE IF NOT EXISTS departments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  session_interval_minutes INTEGER NOT NULL DEFAULT 120 CHECK (session_interval_minutes BETWEEN 15 AND 1440),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO departments (name, session_interval_minutes, active)
SELECT DISTINCT TRIM(jabatan), 120, 1
FROM users
WHERE jabatan IS NOT NULL AND TRIM(jabatan) <> '';

ALTER TABLE users ADD COLUMN department_id INTEGER REFERENCES departments(id);

UPDATE users
SET department_id = (
  SELECT d.id FROM departments d WHERE d.name = users.jabatan LIMIT 1
)
WHERE department_id IS NULL;

CREATE TABLE IF NOT EXISTS checkpoints (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  department_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  nfc_uid TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 1,
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE CASCADE,
  UNIQUE (department_id, name),
  UNIQUE (department_id, nfc_uid)
);

ALTER TABLE nfc_scans ADD COLUMN checkpoint_id INTEGER REFERENCES checkpoints(id);
ALTER TABLE nfc_scans ADD COLUMN session_index INTEGER;

CREATE INDEX IF NOT EXISTS idx_users_department ON users(department_id);
CREATE INDEX IF NOT EXISTS idx_checkpoints_department ON checkpoints(department_id, active, position);
CREATE INDEX IF NOT EXISTS idx_checkpoints_uid ON checkpoints(department_id, nfc_uid);
CREATE INDEX IF NOT EXISTS idx_nfc_scans_checkpoint ON nfc_scans(checkpoint_id);

INSERT OR IGNORE INTO checkpoints (department_id, name, nfc_uid, position)
SELECT id, 'Checkpoint 1', '04:A1:B2:C3:D4:E5:F6', 1 FROM departments;
INSERT OR IGNORE INTO checkpoints (department_id, name, nfc_uid, position)
SELECT id, 'Checkpoint 2', '04:B2:C3:D4:E5:F6:07', 2 FROM departments;
INSERT OR IGNORE INTO checkpoints (department_id, name, nfc_uid, position)
SELECT id, 'Checkpoint 3', '04:C3:D4:E5:F6:07:18', 3 FROM departments;
