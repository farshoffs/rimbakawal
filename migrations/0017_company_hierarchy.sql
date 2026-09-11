CREATE TABLE IF NOT EXISTS companies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE departments ADD COLUMN company_id INTEGER REFERENCES companies(id);
ALTER TABLE users ADD COLUMN company_id INTEGER REFERENCES companies(id);

INSERT OR IGNORE INTO companies (name, active)
SELECT DISTINCT TRIM(company_name), 1
FROM departments
WHERE company_name IS NOT NULL AND TRIM(company_name) <> '';

UPDATE departments
SET company_id = (
  SELECT c.id
  FROM companies c
  WHERE LOWER(c.name) = LOWER(TRIM(departments.company_name))
  LIMIT 1
)
WHERE company_id IS NULL
  AND company_name IS NOT NULL
  AND TRIM(company_name) <> '';

UPDATE users
SET company_id = (
  SELECT d.company_id FROM departments d WHERE d.id = users.department_id
)
WHERE company_id IS NULL AND department_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_departments_company_id ON departments(company_id);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON users(company_id);
