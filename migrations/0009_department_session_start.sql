ALTER TABLE departments ADD COLUMN session_start_minutes INTEGER NOT NULL DEFAULT 420 CHECK (session_start_minutes BETWEEN 0 AND 1439);
