from pathlib import Path

path = Path('worker/index.js')
text = path.read_text()

session_helper = '''function sessionWindow(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  const index = Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
  const startMs = day.startMs + index * safeInterval * 60000;
  return { index, startMs, endMs: Math.min(day.endMs, startMs + safeInterval * 60000) };
}

'''

if 'function sessionWindow(value, interval, startMinutes = 420)' not in text:
    marker = 'function currentSessionIndex(value, interval, startMinutes = 420) {'
    if marker not in text:
        raise SystemExit('currentSessionIndex marker not found')
    text = text.replace(marker, session_helper + marker, 1)

new_get_scans = r'''async function getScans(request, env, url) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const requestedDate = url.searchParams.get('date') || malaysiaDateKey(new Date());
  if (!/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)) {
    return json({ error: 'Tarikh tidak sah.' }, 400);
  }

  const calendarBounds = malaysiaDayBounds(requestedDate);
  if (!calendarBounds) return json({ error: 'Tarikh tidak sah.' }, 400);

  const sessionStartMinutes = Math.max(
    0,
    Math.min(1439, Number(auth.user.session_start_minutes ?? 420)),
  );
  const interval = Math.max(
    15,
    Math.min(1440, Number(auth.user.session_interval_minutes || 120)),
  );

  // Query enough data to evaluate complete session windows at the edges of
  // the selected Malaysia calendar date, while only displaying scans that
  // actually happened on the selected date.
  const firstWindow = sessionWindow(
    new Date(calendarBounds.startMs),
    interval,
    sessionStartMinutes,
  );
  const lastWindow = sessionWindow(
    new Date(calendarBounds.endMs - 1),
    interval,
    sessionStartMinutes,
  );
  const queryStartIso = new Date(firstWindow.startMs).toISOString();
  const queryEndIso = new Date(lastWindow.endMs).toISOString();

  const checkpointResult = await env.DB.prepare(
    `SELECT id, name, position
     FROM checkpoints
     WHERE department_id = ? AND active = 1
     ORDER BY position ASC, id ASC`,
  ).bind(auth.user.department_id).all();
  const checkpoints = checkpointResult.results ?? [];

  const scanResult = await env.DB.prepare(
    `SELECT s.id, s.user_id, s.nfc_uid, s.scanned_at, s.checkpoint_id,
            s.session_index, c.name AS checkpoint_name,
            u.nama AS user_name, u.profile_picture
     FROM nfc_scans s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
     WHERE u.department_id = ? AND s.scanned_at >= ? AND s.scanned_at < ?
     ORDER BY s.scanned_at ASC, s.id ASC`,
  ).bind(auth.user.department_id, queryStartIso, queryEndIso).all();

  const scans = scanResult.results ?? [];
  const nowMs = Date.now();
  const todayKey = malaysiaDateKey(new Date());
  const isPastDay = requestedDate < todayKey;
  const isFutureDay = requestedDate > todayKey;
  const sessions = [];

  if (!isFutureDay) {
    let cursor = firstWindow.startMs;
    while (cursor < calendarBounds.endMs) {
      const window = sessionWindow(
        new Date(cursor),
        interval,
        sessionStartMinutes,
      );
      const startMs = window.startMs;
      const endMs = window.endMs;
      if (startMs >= calendarBounds.endMs) break;
      if (requestedDate === todayKey && startMs > nowMs) break;

      const fullSessionScans = scans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= startMs && time < endMs;
      });
      const calendarScans = fullSessionScans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= calendarBounds.startMs && time < calendarBounds.endMs;
      });

      const scannedCheckpointIds = new Set(
        fullSessionScans
          .map((scan) => Number(scan.checkpoint_id || 0))
          .filter((id) => id > 0),
      );
      const missing = checkpoints.filter(
        (checkpoint) => !scannedCheckpointIds.has(Number(checkpoint.id)),
      );

      let status = 'in_progress';
      if (checkpoints.length === 0) status = 'no_checkpoints';
      else if (missing.length === 0) status = 'complete';
      else if (isPastDay || endMs <= nowMs) status = 'missed';

      const scannerIds = [...new Set(
        calendarScans
          .map((scan) => Number(scan.user_id || 0))
          .filter((id) => id > 0),
      )];
      const scannerNames = [...new Set(
        calendarScans
          .map((scan) => String(scan.user_name || '').trim())
          .filter(Boolean),
      )];
      const firstScan = calendarScans[0] ?? null;

      sessions.push({
        userId: scannerIds.length === 1 ? scannerIds[0] : 0,
        userName: scannerNames.length > 0
          ? scannerNames.join(', ')
          : 'Tiada pengawal direkodkan',
        profilePicture: scannerIds.length === 1
          ? (firstScan?.profile_picture || null)
          : null,
        index: window.index,
        startAt: new Date(startMs).toISOString(),
        endAt: new Date(endMs).toISOString(),
        status,
        expectedCount: checkpoints.length,
        scannedCount: scannedCheckpointIds.size,
        missingCheckpoints: missing.map((checkpoint) => ({
          id: checkpoint.id,
          name: checkpoint.name,
          position: checkpoint.position,
        })),
        scans: calendarScans.map(scanJson),
      });

      if (endMs <= cursor) break;
      cursor = endMs;
    }
    sessions.sort((left, right) => Date.parse(right.startAt) - Date.parse(left.startAt));
  }

  return json({
    date: requestedDate,
    department: auth.user.jabatan,
    sessionIntervalMinutes: interval,
    sessionStartMinutes,
    checkpoints,
    sessions,
  });
}

'''

start = text.find('async function getScans(request, env, url) {')
end = text.find('async function createScan(request, env) {')
if start < 0 or end < 0 or end <= start:
    raise SystemExit('getScans block markers not found')
text = text[:start] + new_get_scans + text[end:]

if text.count('function sessionWindow(value, interval, startMinutes = 420)') != 1:
    raise SystemExit('sessionWindow helper count is not exactly one')
if "const todayKey = malaysiaDateKey(new Date());" not in text:
    raise SystemExit('calendar-date history guard missing')
if 'scans: calendarScans.map(scanJson)' not in text:
    raise SystemExit('calendar-date scan display guard missing')

path.write_text(text)
print('Patrol history hotfix applied.')
