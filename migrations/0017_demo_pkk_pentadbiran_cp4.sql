-- Ensure the Pentadbiran presentation dataset has at least four active
-- checkpoints so PKK 4 visually matches the supplied four-checkpoint example.

INSERT OR IGNORE INTO checkpoints
  (department_id, name, nfc_uid, position, active)
SELECT
  d.id,
  'CP4',
  'TEXT:RIMBAKAWAL-PENTADBIRAN-DEMO-CP4-V2',
  4,
  1
FROM departments d
WHERE d.name = 'Pentadbiran'
  AND (
    SELECT COUNT(*)
    FROM checkpoints c
    WHERE c.department_id = d.id
      AND c.active = 1
  ) < 4;

-- Rebuild only the tagged presentation scan set so the new CP4 receives the
-- same realistic August 2026 scan history. Operational/non-demo scans remain untouched.
DELETE FROM nfc_scans
WHERE client_event_id LIKE 'DEMO-PKK4-202608-%';

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
