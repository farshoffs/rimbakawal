ALTER TABLE nfc_scans ADD COLUMN client_event_id TEXT;
ALTER TABLE incident_reports ADD COLUMN client_event_id TEXT;
ALTER TABLE sos_events ADD COLUMN client_event_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_nfc_scans_client_event
  ON nfc_scans(client_event_id)
  WHERE client_event_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_incident_reports_client_event
  ON incident_reports(client_event_id)
  WHERE client_event_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sos_events_client_event
  ON sos_events(client_event_id)
  WHERE client_event_id IS NOT NULL;
