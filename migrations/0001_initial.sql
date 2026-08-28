CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nama TEXT NOT NULL,
  no_kad_pengenalan TEXT NOT NULL UNIQUE,
  jawatan TEXT NOT NULL,
  profile_picture TEXT,
  jabatan TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_hash TEXT NOT NULL UNIQUE,
  user_id INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS nfc_scans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  nfc_uid TEXT NOT NULL,
  scanned_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at_ms);
CREATE INDEX IF NOT EXISTS idx_nfc_scans_user_time ON nfc_scans(user_id, scanned_at DESC);

INSERT OR IGNORE INTO users (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan)
VALUES
  ('MUHAMMAD FARHAN BIN SHOFFI', '000000000001', 'Management', NULL, 'Pentadbiran'),
  ('AHMAD HAKIM BIN RAZAK', '000000000002', 'Patrol', NULL, 'Operasi Rondaan'),
  ('NUR AINA BINTI SALLEH', '000000000003', 'Patrol', NULL, 'Operasi Rondaan'),
  ('MUHAMMAD DANIAL BIN AZMI', '000000000004', 'Patrol', NULL, 'Operasi Rondaan');
