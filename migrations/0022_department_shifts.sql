CREATE TABLE IF NOT EXISTS department_shifts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  department_id INTEGER NOT NULL,
  shift_number INTEGER NOT NULL CHECK (shift_number BETWEEN 1 AND 3),
  start_minutes INTEGER NOT NULL CHECK (start_minutes BETWEEN 0 AND 1439),
  end_minutes INTEGER NOT NULL CHECK (end_minutes BETWEEN 0 AND 1439),
  required_guards INTEGER NOT NULL DEFAULT 0 CHECK (required_guards BETWEEN 0 AND 99),
  active INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (department_id, shift_number),
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_department_shifts_department_active
  ON department_shifts (department_id, active, shift_number);

-- Existing schools keep the current PKK convention as a safe default.
-- Guard requirements stay blank/zero until Management sets the contractual value.
INSERT OR IGNORE INTO department_shifts (
  department_id, shift_number, start_minutes, end_minutes, required_guards, active
)
SELECT id, 1, 480, 1200, 0, 1 FROM departments;

INSERT OR IGNORE INTO department_shifts (
  department_id, shift_number, start_minutes, end_minutes, required_guards, active
)
SELECT id, 2, 1200, 480, 0, 1 FROM departments;
