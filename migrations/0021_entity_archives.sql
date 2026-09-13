CREATE TABLE IF NOT EXISTS entity_archives (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL CHECK(entity_type IN ('company', 'department')),
  entity_id INTEGER NOT NULL,
  snapshot_json TEXT NOT NULL,
  archived_by INTEGER,
  archived_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  restored_at TEXT,
  restored_by INTEGER
);

CREATE INDEX IF NOT EXISTS idx_entity_archives_lookup
  ON entity_archives(entity_type, entity_id, restored_at, id);
