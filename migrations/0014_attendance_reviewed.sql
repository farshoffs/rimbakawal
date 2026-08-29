ALTER TABLE attendance_records ADD COLUMN reviewed_at TEXT;
ALTER TABLE attendance_records ADD COLUMN reviewed_by INTEGER;
CREATE INDEX IF NOT EXISTS idx_attendance_records_reviewed
  ON attendance_records(work_date, reviewed_at);
