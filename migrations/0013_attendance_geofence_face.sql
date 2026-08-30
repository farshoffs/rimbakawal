ALTER TABLE departments ADD COLUMN attendance_latitude REAL;
ALTER TABLE departments ADD COLUMN attendance_longitude REAL;
ALTER TABLE departments ADD COLUMN attendance_radius_meters INTEGER NOT NULL DEFAULT 200;

CREATE TABLE attendance_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('in', 'out')),
  status TEXT NOT NULL CHECK (status IN ('accepted', 'rejected')),
  rejection_reason TEXT,
  recorded_at TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracy REAL,
  distance_meters REAL NOT NULL,
  geofence_radius_meters INTEGER NOT NULL,
  within_geofence INTEGER NOT NULL CHECK (within_geofence IN (0, 1)),
  face_detected INTEGER NOT NULL CHECK (face_detected IN (0, 1)),
  face_matched INTEGER NOT NULL CHECK (face_matched IN (0, 1)),
  face_similarity REAL,
  face_threshold REAL NOT NULL,
  face_reference_source TEXT NOT NULL DEFAULT 'profile_picture',
  selfie_image TEXT NOT NULL,
  device_platform TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (department_id) REFERENCES departments(id)
);

CREATE INDEX idx_attendance_user_recorded
  ON attendance_records(user_id, recorded_at DESC);
CREATE INDEX idx_attendance_department_recorded
  ON attendance_records(department_id, recorded_at DESC);
CREATE INDEX idx_attendance_status_recorded
  ON attendance_records(status, recorded_at DESC);
