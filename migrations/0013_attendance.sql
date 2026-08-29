-- Attendance/geofence + face verification
ALTER TABLE departments ADD COLUMN attendance_latitude REAL;
ALTER TABLE departments ADD COLUMN attendance_longitude REAL;
ALTER TABLE departments ADD COLUMN attendance_radius_m INTEGER NOT NULL DEFAULT 150;
ALTER TABLE departments ADD COLUMN attendance_location_label TEXT;

CREATE TABLE IF NOT EXISTS attendance_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER NOT NULL,
  work_date TEXT NOT NULL,
  punch_type TEXT NOT NULL CHECK (punch_type IN ('IN', 'OUT')),
  punched_at TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracy_m REAL,
  distance_m REAL NOT NULL,
  selfie_data TEXT NOT NULL,
  profile_picture_hash TEXT,
  face_status TEXT NOT NULL DEFAULT 'review_required',
  face_score REAL,
  face_model TEXT,
  face_reason TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(department_id) REFERENCES departments(id)
);

CREATE INDEX IF NOT EXISTS idx_attendance_user_date
  ON attendance_records(user_id, work_date, punched_at DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_department_date
  ON attendance_records(department_id, work_date, punched_at DESC);
