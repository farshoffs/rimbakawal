-- ZPatrol official Company hierarchy alignment.
-- This migration only aligns existing records. It intentionally inserts no dummy data.

INSERT OR IGNORE INTO companies (name, active, updated_at)
SELECT DISTINCT TRIM(company_name), 1, CURRENT_TIMESTAMP
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

UPDATE departments
SET company_name = (
  SELECT c.name FROM companies c WHERE c.id = departments.company_id
), updated_at = CURRENT_TIMESTAMP
WHERE company_id IS NOT NULL;

UPDATE users
SET company_id = (
  SELECT d.company_id FROM departments d WHERE d.id = users.department_id
)
WHERE company_id IS NULL
  AND department_id IS NOT NULL
  AND LOWER(jawatan) = 'administration';

UPDATE users
SET company_id = (
  SELECT d.company_id FROM departments d WHERE d.id = users.department_id
)
WHERE department_id IS NOT NULL
  AND LOWER(jawatan) IN ('patrol', 'supervisor');

UPDATE users
SET jabatan = (
  SELECT d.name FROM departments d WHERE d.id = users.department_id
)
WHERE department_id IS NOT NULL
  AND LOWER(jawatan) IN ('patrol', 'supervisor');

UPDATE users
SET jabatan = (
  SELECT c.name FROM companies c WHERE c.id = users.company_id
)
WHERE company_id IS NOT NULL
  AND LOWER(jawatan) = 'administration';

UPDATE users
SET department_id = NULL
WHERE company_id IS NOT NULL
  AND LOWER(jawatan) = 'administration';

CREATE INDEX IF NOT EXISTS idx_companies_active_name ON companies(active, name);
