-- Presentation/demo data for Jana Laporan PKK 2, PKK 3 and PKK 4.
-- This is real D1 data (not hardcoded in Flutter) and is isolated by synthetic ICs
-- 990101020001..004 plus client_event_id prefix DEMO-PKK4-202608-.
-- Report month: OGOS 2026. Department: Pentadbiran.

INSERT OR IGNORE INTO departments (name, session_interval_minutes, active)
VALUES ('Pentadbiran', 120, 1);

-- Keep any real metadata already configured. Fill blanks only so the demo PDF
-- has presentable company/zone fields without overwriting production values.
UPDATE departments
SET company_name = CASE
      WHEN company_name IS NULL OR TRIM(company_name) = ''
        THEN 'SENTINEL SECURITY SERVICES SDN BHD'
      ELSE company_name
    END,
    zone = CASE
      WHEN zone IS NULL OR TRIM(zone) = ''
        THEN 'KUALA MUDA 1'
      ELSE zone
    END
WHERE name = 'Pentadbiran';

-- Four fictional guards. Their synthetic IC numbers are the stable demo marker.
INSERT OR IGNORE INTO users
  (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, department_id, no_pk)
SELECT 'AHMAD FIRDAUS BIN RAZALI', '990101020001', 'Patrol', NULL,
       'Pentadbiran', id, '101'
FROM departments WHERE name = 'Pentadbiran';

INSERT OR IGNORE INTO users
  (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, department_id, no_pk)
SELECT 'MUHAMMAD HAZIQ BIN ZAKARIA', '990101020002', 'Patrol', NULL,
       'Pentadbiran', id, '102'
FROM departments WHERE name = 'Pentadbiran';

INSERT OR IGNORE INTO users
  (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, department_id, no_pk)
SELECT 'NURUL AINA BINTI HASSAN', '990101020003', 'Patrol', NULL,
       'Pentadbiran', id, '103'
FROM departments WHERE name = 'Pentadbiran';

INSERT OR IGNORE INTO users
  (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, department_id, no_pk)
SELECT 'SITI HAWA BINTI ISMAIL', '990101020004', 'Patrol', NULL,
       'Pentadbiran', id, '104'
FROM departments WHERE name = 'Pentadbiran';

UPDATE users
SET active = 1,
    jawatan = 'Patrol',
    jabatan = 'Pentadbiran',
    department_id = (SELECT id FROM departments WHERE name = 'Pentadbiran'),
    no_pk = CASE no_kad_pengenalan
      WHEN '990101020001' THEN '101'
      WHEN '990101020002' THEN '102'
      WHEN '990101020003' THEN '103'
      WHEN '990101020004' THEN '104'
      ELSE no_pk
    END
WHERE no_kad_pengenalan IN (
  '990101020001', '990101020002', '990101020003', '990101020004'
);

-- Pentadbiran normally already has Checkpoint 1-3 from the base seed. Add a
-- fourth presentation point if it does not exist; do not rename/delete real points.
INSERT OR IGNORE INTO checkpoints
  (department_id, name, nfc_uid, position, active)
SELECT id, 'Checkpoint 4', 'TEXT:RIMBAKAWAL-PENTADBIRAN-DEMO-CP4', 4, 1
FROM departments
WHERE name = 'Pentadbiran';

-- Remove only this migration's previous attendance dataset if the SQL is ever
-- re-applied manually. Real attendance is untouched.
DELETE FROM attendance_records
WHERE user_id IN (
  SELECT id FROM users
  WHERE no_kad_pengenalan IN (
    '990101020001', '990101020002', '990101020003', '990101020004'
  )
)
AND punched_at >= '2026-07-31T16:00:00Z'
AND punched_at <  '2026-09-02T16:00:00Z';

-- One day guard + one night guard per date, alternating between two guards.
-- This gives every guard about 15-16 realistic shifts, so each PKK 3 page is
-- populated but not excessively long. Night OUT can cross into the next day.
WITH RECURSIVE days(day) AS (
  SELECT 1
  UNION ALL
  SELECT day + 1 FROM days WHERE day < 31
),
punches AS (
  SELECT
    day,
    CASE WHEN (day % 2) = 1 THEN '990101020001' ELSE '990101020002' END AS ic,
    'IN' AS punch_type,
    470 + (day % 6) AS local_minute
  FROM days
  UNION ALL
  SELECT
    day,
    CASE WHEN (day % 2) = 1 THEN '990101020001' ELSE '990101020002' END,
    'OUT',
    1190 + ((day + 2) % 6)
  FROM days
  UNION ALL
  SELECT
    day,
    CASE WHEN (day % 2) = 1 THEN '990101020003' ELSE '990101020004' END,
    'IN',
    1188 + (day % 7)
  FROM days
  UNION ALL
  SELECT
    day,
    CASE WHEN (day % 2) = 1 THEN '990101020003' ELSE '990101020004' END,
    'OUT',
    1908 + ((day + 3) % 7)
  FROM days
)
INSERT INTO attendance_records (
  user_id,
  department_id,
  work_date,
  punch_type,
  punched_at,
  latitude,
  longitude,
  accuracy_m,
  distance_m,
  selfie_data,
  profile_picture_hash,
  face_status,
  face_score,
  face_model,
  face_reason
)
SELECT
  u.id,
  d.id,
  printf('2026-08-%02d', p.day),
  p.punch_type,
  strftime(
    '%Y-%m-%dT%H:%M:%SZ',
    datetime(
      printf('2026-08-%02d 00:00:00', p.day),
      printf('+%d minutes', p.local_minute),
      '-8 hours'
    )
  ),
  COALESCE(d.attendance_latitude, 0.0),
  COALESCE(d.attendance_longitude, 0.0),
  5.0,
  0.0,
  'demo://rimbakawal-pkk-presentation',
  'DEMO-PKK-202608',
  'verified',
  0.98,
  'demo-presentation',
  'Data demonstrasi Jana Laporan PKK'
FROM punches p
JOIN users u ON u.no_kad_pengenalan = p.ic
JOIN departments d ON d.name = 'Pentadbiran';

-- Re-applying manually stays safe because demo scans carry a stable prefix.
DELETE FROM nfc_scans
WHERE client_event_id LIKE 'DEMO-PKK4-202608-%';

-- PKK 4: generate a realistic guard-tour matrix from 10-31 Aug 2026.
-- Every active Pentadbiran checkpoint is scanned once in each 2-hour slot.
-- Three selected misses are intentional so the presentation can show 11 / 12
-- as well as perfect 12 / 12 summaries.
WITH RECURSIVE
  days(day) AS (
    SELECT 10
    UNION ALL
    SELECT day + 1 FROM days WHERE day < 31
  ),
  slots(slot) AS (
    SELECT 0
    UNION ALL
    SELECT slot + 1 FROM slots WHERE slot < 11
  ),
  demo_checkpoints AS (
    SELECT c.id, c.nfc_uid, c.position
    FROM checkpoints c
    JOIN departments d ON d.id = c.department_id
    WHERE d.name = 'Pentadbiran'
      AND c.active = 1
  ),
  scan_plan AS (
    SELECT
      days.day,
      slots.slot,
      cp.id AS checkpoint_id,
      cp.nfc_uid,
      cp.position,
      CASE
        WHEN slots.slot BETWEEN 4 AND 9
          THEN CASE WHEN (days.day % 2) = 1
            THEN '990101020001' ELSE '990101020002' END
        ELSE CASE WHEN (days.day % 2) = 1
          THEN '990101020003' ELSE '990101020004' END
      END AS guard_ic
    FROM days
    CROSS JOIN slots
    CROSS JOIN demo_checkpoints cp
    WHERE NOT (
      (days.day = 14 AND cp.position = 4 AND slots.slot = 6)
      OR (days.day = 19 AND cp.position = 2 AND slots.slot = 3)
      OR (days.day = 23 AND cp.position = 3 AND slots.slot = 10)
    )
  )
INSERT OR IGNORE INTO nfc_scans (
  user_id,
  nfc_uid,
  scanned_at,
  checkpoint_id,
  session_index,
  client_event_id,
  client_session_id
)
SELECT
  u.id,
  sp.nfc_uid,
  strftime(
    '%Y-%m-%dT%H:%M:%SZ',
    datetime(
      printf('2026-08-%02d 00:00:00', sp.day),
      printf(
        '+%d minutes',
        (sp.slot * 120) + 4 + ((COALESCE(sp.position, 1) * 5) % 34)
      ),
      '-8 hours'
    )
  ),
  sp.checkpoint_id,
  sp.slot + 1,
  printf(
    'DEMO-PKK4-202608-D%02d-S%02d-CP%d',
    sp.day,
    sp.slot + 1,
    sp.checkpoint_id
  ),
  printf('DEMO-PKK4-202608-D%02d-S%02d', sp.day, sp.slot + 1)
FROM scan_plan sp
JOIN users u ON u.no_kad_pengenalan = sp.guard_ic;
