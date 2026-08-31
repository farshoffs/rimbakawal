import attendanceWorker from './attendance.js';

const SESSION_COOKIE = 'rk_session';
const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/api/admin/command-center' && request.method === 'GET') {
      try {
        return await commandCenterRange(request, env, url);
      } catch (error) {
        console.error('period command center failed', error);
        return json({ error: 'Ralat pemantauan tempoh. Sila cuba lagi.' }, 500);
      }
    }
    return attendanceWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    if (typeof attendanceWorker.scheduled === 'function') {
      return attendanceWorker.scheduled(event, env, ctx);
    }
  },
};

async function commandCenterRange(request, env, url) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;

  const now = new Date();
  const nowMs = now.getTime();
  const todayKey = malaysiaDateKey(now);
  const from = url.searchParams.get('from') || todayKey;
  const to = url.searchParams.get('to') || from;
  const mode = String(url.searchParams.get('mode') || 'day').toLowerCase();
  if (!isDateKey(from) || !isDateKey(to) || from > to) {
    return json({ error: 'Julat tarikh pemantauan tidak sah.' }, 400);
  }
  const fromBounds = malaysiaDayBounds(from);
  const toBounds = malaysiaDayBounds(to);
  if (!fromBounds || !toBounds) {
    return json({ error: 'Julat tarikh pemantauan tidak sah.' }, 400);
  }
  const span = Math.round((toBounds.endMs - fromBounds.startMs) / DAY_MS);
  if (span < 1 || span > 31) {
    return json({ error: 'Tempoh pemantauan maksimum ialah 31 hari.' }, 400);
  }

  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const scopeDepartment = role === 'management'
    ? null
    : Number(auth.user.department_id || 0) || null;
  const includesToday = from <= todayKey && to >= todayKey;
  const rangeStartIso = fromBounds.startIso;
  const rangeEndIso = toBounds.endIso;
  const liveSince = new Date(nowMs - 2 * 60 * 1000).toISOString();

  const [
    usersResult,
    checkpointsResult,
    scansResult,
    attendanceResult,
    incidentsResult,
    sosResult,
    activePatrolResult,
  ] = await Promise.all([
    env.DB.prepare(
      `SELECT u.id, u.nama, u.department_id,
              COALESCE(d.name, u.jabatan) AS jabatan,
              u.profile_picture,
              COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
              COALESCE(d.session_start_minutes, 420) AS session_start_minutes
       FROM users u
       LEFT JOIN departments d ON d.id = u.department_id
       WHERE u.active = 1
         AND LOWER(u.jawatan) IN ('patrol', 'supervisor')
         ${scopeDepartment ? 'AND u.department_id = ?' : ''}
       ORDER BY jabatan ASC, u.nama ASC`,
    ).bind(...(scopeDepartment ? [scopeDepartment] : [])).all(),
    env.DB.prepare(
      `SELECT c.id, c.department_id, c.name, c.position,
              COALESCE(d.name, 'Jabatan') AS department_name
       FROM checkpoints c
       LEFT JOIN departments d ON d.id = c.department_id
       WHERE c.active = 1
         ${scopeDepartment ? 'AND c.department_id = ?' : ''}
       ORDER BY c.department_id ASC, c.position ASC, c.id ASC`,
    ).bind(...(scopeDepartment ? [scopeDepartment] : [])).all(),
    env.DB.prepare(
      `SELECT s.id, s.user_id, s.checkpoint_id, s.session_index,
              s.client_session_id, s.scanned_at
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       WHERE s.scanned_at >= ? AND s.scanned_at < ?
         ${scopeDepartment ? 'AND u.department_id = ?' : ''}
       ORDER BY s.scanned_at ASC, s.id ASC`,
    ).bind(...(scopeDepartment
      ? [rangeStartIso, rangeEndIso, scopeDepartment]
      : [rangeStartIso, rangeEndIso])).all(),
    env.DB.prepare(
      `SELECT a.id, a.user_id, a.department_id, a.work_date,
              a.punch_type, a.punched_at, a.distance_m,
              a.face_status, a.face_score,
              u.nama, COALESCE(d.name, u.jabatan) AS department_name
       FROM attendance_records a
       JOIN users u ON u.id = a.user_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE a.work_date >= ? AND a.work_date <= ?
         AND u.active = 1
         AND LOWER(u.jawatan) IN ('patrol', 'supervisor')
         ${scopeDepartment ? 'AND a.department_id = ?' : ''}
       ORDER BY a.punched_at ASC, a.id ASC`,
    ).bind(...(scopeDepartment ? [from, to, scopeDepartment] : [from, to])).all(),
    env.DB.prepare(
      `SELECT i.id, i.department_id, i.category, i.severity, i.note,
              i.status, i.created_at, u.nama,
              COALESCE(d.name, u.jabatan) AS jabatan,
              c.name AS checkpoint_name,
              (SELECT COUNT(*) FROM incident_images ii WHERE ii.incident_id = i.id) AS image_count
       FROM incident_reports i
       JOIN users u ON u.id = i.user_id
       LEFT JOIN departments d ON d.id = i.department_id
       LEFT JOIN checkpoints c ON c.id = i.checkpoint_id
       WHERE i.created_at >= ? AND i.created_at < ?
         ${scopeDepartment ? 'AND i.department_id = ?' : ''}
       ORDER BY i.created_at DESC
       LIMIT 100`,
    ).bind(...(scopeDepartment
      ? [rangeStartIso, rangeEndIso, scopeDepartment]
      : [rangeStartIso, rangeEndIso])).all(),
    env.DB.prepare(
      `SELECT e.id, e.department_id, e.triggered_at, e.note,
              u.nama, COALESCE(d.name, u.jabatan) AS jabatan
       FROM sos_events e
       JOIN users u ON u.id = e.user_id
       LEFT JOIN departments d ON d.id = e.department_id
       WHERE e.triggered_at >= ? AND e.triggered_at < ?
         ${scopeDepartment ? 'AND e.department_id = ?' : ''}
       ORDER BY e.triggered_at DESC
       LIMIT 100`,
    ).bind(...(scopeDepartment
      ? [rangeStartIso, rangeEndIso, scopeDepartment]
      : [rangeStartIso, rangeEndIso])).all(),
    includesToday
      ? env.DB.prepare(
          `SELECT ps.id, ps.user_id, ps.started_at,
                  ps.last_latitude, ps.last_longitude,
                  ps.last_accuracy, ps.last_location_at
           FROM patrol_sessions ps
           JOIN users u ON u.id = ps.user_id
           JOIN (
             SELECT user_id, MAX(id) AS latest_id
             FROM patrol_sessions
             WHERE status = 'active'
               AND COALESCE(last_location_at, started_at) >= ?
             GROUP BY user_id
           ) latest ON latest.latest_id = ps.id
           ${scopeDepartment ? 'WHERE u.department_id = ?' : ''}`,
        ).bind(...(scopeDepartment ? [liveSince, scopeDepartment] : [liveSince])).all()
      : Promise.resolve({ results: [] }),
  ]);

  const users = usersResult.results ?? [];
  const userById = new Map(users.map((row) => [Number(row.id), row]));
  const usersByDepartment = new Map();
  for (const user of users) {
    const departmentId = Number(user.department_id || 0);
    if (departmentId <= 0) continue;
    const list = usersByDepartment.get(departmentId) ?? [];
    list.push(user);
    usersByDepartment.set(departmentId, list);
  }

  const checkpoints = checkpointsResult.results ?? [];
  const checkpointsByDepartment = new Map();
  const departmentNames = new Map();
  for (const checkpoint of checkpoints) {
    const departmentId = Number(checkpoint.department_id || 0);
    const list = checkpointsByDepartment.get(departmentId) ?? [];
    list.push(checkpoint);
    checkpointsByDepartment.set(departmentId, list);
    departmentNames.set(departmentId, checkpoint.department_name || 'Jabatan');
  }
  for (const user of users) {
    departmentNames.set(Number(user.department_id || 0), user.jabatan || 'Jabatan');
  }

  const scans = scansResult.results ?? [];
  const scansByDepartment = new Map();
  for (const scan of scans) {
    const user = userById.get(Number(scan.user_id));
    if (!user) continue;
    const departmentId = Number(user.department_id || 0);
    const list = scansByDepartment.get(departmentId) ?? [];
    list.push(scan);
    scansByDepartment.set(departmentId, list);
  }

  const activePatrols = new Map(
    (activePatrolResult.results ?? []).map((row) => [Number(row.user_id), row]),
  );

  let completeSessions = 0;
  let missedSessions = 0;
  let missedCheckpoints = 0;
  let scannedCheckpoints = 0;
  let dueCheckpoints = 0;
  let completedScannedCheckpoints = 0;
  let currentAlerts = 0;
  const coverageDays = [];
  const missedDetails = [];

  for (let dayMs = fromBounds.startMs; dayMs < toBounds.endMs; dayMs += DAY_MS) {
    const dayKey = malaysiaDateKey(new Date(dayMs + 12 * 60 * 60 * 1000));
    const dayBounds = malaysiaDayBounds(dayKey);
    if (!dayBounds) continue;

    for (const [departmentId, departmentUsers] of usersByDepartment.entries()) {
      const expectedRows = checkpointsByDepartment.get(departmentId) ?? [];
      const expected = expectedRows.length;
      if (expected <= 0) continue;

      const sample = departmentUsers[0];
      const interval = Math.max(15, Number(sample.session_interval_minutes || 120));
      const intervalMs = interval * 60000;
      const startMinutes = Math.max(0, Math.min(1439, Number(sample.session_start_minutes ?? 420)));
      const anchorMs = dayBounds.startMs + startMinutes * 60000;
      const departmentScans = (scansByDepartment.get(departmentId) ?? []).filter((row) => {
        const stamp = Date.parse(row.scanned_at);
        return stamp >= dayBounds.startMs && stamp < dayBounds.endMs;
      });

      let dayDueSessions = 0;
      let dayCompleteSessions = 0;
      let dayMissedSessions = 0;
      let dayScanned = 0;
      let dayMissedCheckpoints = 0;
      let dayDueCheckpoints = 0;

      for (let index = 0; ; index += 1) {
        const sessionStartMs = anchorMs + index * intervalMs;
        if (sessionStartMs >= dayBounds.endMs) break;
        const sessionEndMs = Math.min(dayBounds.endMs, sessionStartMs + intervalMs);
        const isDue = sessionEndMs <= nowMs;
        const isCurrent = includesToday
          && dayKey === todayKey
          && sessionStartMs <= nowMs
          && nowMs < sessionEndMs;
        if (!isDue && !isCurrent) continue;

        const rows = departmentScans.filter((row) => {
          const stamp = Date.parse(row.scanned_at);
          return stamp >= sessionStartMs && stamp < sessionEndMs;
        });
        const unique = new Set(
          rows.map((row) => Number(row.checkpoint_id || 0)).filter((id) => id > 0),
        );
        dayScanned += unique.size;
        scannedCheckpoints += unique.size;

        if (isCurrent && !isDue) {
          const hasActivePatroller = departmentUsers.some((user) => activePatrols.has(Number(user.id)));
          const minutesInto = Math.max(0, Math.floor((nowMs - sessionStartMs) / 60000));
          const grace = Math.max(10, Math.min(30, Math.floor(interval / 4)));
          if (hasActivePatroller && minutesInto >= grace && unique.size === 0) {
            currentAlerts += 1;
          }
          continue;
        }

        dayDueSessions += 1;
        dayDueCheckpoints += expected;
        dueCheckpoints += expected;
        completedScannedCheckpoints += unique.size;
        if (unique.size >= expected) {
          completeSessions += 1;
          dayCompleteSessions += 1;
          continue;
        }

        const missing = expectedRows
          .filter((checkpoint) => !unique.has(Number(checkpoint.id)))
          .map((checkpoint) => ({
            id: Number(checkpoint.id),
            name: checkpoint.name,
            position: Number(checkpoint.position || 0),
          }));
        missedSessions += 1;
        dayMissedSessions += 1;
        missedCheckpoints += missing.length;
        dayMissedCheckpoints += missing.length;
        if (missedDetails.length < 500) {
          missedDetails.push({
            date: dayKey,
            departmentId,
            department: departmentNames.get(departmentId) || 'Jabatan',
            sessionIndex: index + 1,
            sessionStartAt: new Date(sessionStartMs).toISOString(),
            sessionEndAt: new Date(sessionEndMs).toISOString(),
            expectedCount: expected,
            scannedCount: unique.size,
            missingCheckpoints: missing,
          });
        }
      }

      if (dayDueSessions > 0 || dayScanned > 0) {
        coverageDays.push({
          date: dayKey,
          departmentId,
          department: departmentNames.get(departmentId) || 'Jabatan',
          dueSessions: dayDueSessions,
          completeSessions: dayCompleteSessions,
          missedSessions: dayMissedSessions,
          scannedCheckpoints: dayScanned,
          missedCheckpoints: dayMissedCheckpoints,
          dueCheckpoints: dayDueCheckpoints,
        });
      }
    }
  }

  const attendance = attendanceResult.results ?? [];
  const presentUsers = new Set();
  const attendanceDays = new Set();
  let faceReviewRequired = 0;
  for (const row of attendance) {
    if (row.punch_type === 'IN') {
      presentUsers.add(Number(row.user_id));
      attendanceDays.add(`${row.user_id}:${row.work_date}`);
    }
    if (row.face_status === 'review_required') faceReviewRequired += 1;
  }

  let currentlyIn = 0;
  if (includesToday) {
    const latestToday = new Map();
    for (const row of attendance) {
      if (row.work_date !== todayKey) continue;
      const userId = Number(row.user_id);
      const existing = latestToday.get(userId);
      if (!existing || Date.parse(row.punched_at) > Date.parse(existing.punched_at)) {
        latestToday.set(userId, row);
      }
    }
    currentlyIn = [...latestToday.values()].filter((row) => row.punch_type === 'IN').length;
  }

  const recentAttendance = [...attendance]
    .sort((a, b) => Date.parse(b.punched_at) - Date.parse(a.punched_at))
    .slice(0, 12)
    .map((row) => ({
      id: Number(row.id),
      userId: Number(row.user_id),
      userName: row.nama,
      department: row.department_name,
      punchType: row.punch_type,
      punchedAt: row.punched_at,
      distanceMeters: Number(row.distance_m || 0),
      faceStatus: row.face_status,
      faceScore: row.face_score == null ? null : Number(row.face_score),
      workDate: row.work_date,
    }));

  const activity = new Map();
  for (const scan of scans) {
    const user = userById.get(Number(scan.user_id));
    if (!user) continue;
    const userId = Number(user.id);
    const current = activity.get(userId) ?? {
      userId,
      departmentId: Number(user.department_id || 0),
      nama: user.nama,
      jabatan: user.jabatan,
      profilePicture: user.profile_picture || null,
      scanCount: 0,
      activeDaysSet: new Set(),
      sessionsSet: new Set(),
      lastScanAt: null,
    };
    current.scanCount += 1;
    current.activeDaysSet.add(malaysiaDateKey(new Date(scan.scanned_at)));
    current.sessionsSet.add(
      scan.client_session_id || `${malaysiaDateKey(new Date(scan.scanned_at))}:${scan.session_index ?? '-'}`,
    );
    if (!current.lastScanAt || Date.parse(scan.scanned_at) > Date.parse(current.lastScanAt)) {
      current.lastScanAt = scan.scanned_at;
    }
    activity.set(userId, current);
  }
  const guardActivity = [...activity.values()]
    .map((row) => ({
      userId: row.userId,
      departmentId: row.departmentId,
      nama: row.nama,
      jabatan: row.jabatan,
      profilePicture: row.profilePicture,
      scanCount: row.scanCount,
      activeDays: row.activeDaysSet.size,
      sessionCount: row.sessionsSet.size,
      lastScanAt: row.lastScanAt,
      currentlyPatrolling: activePatrols.has(row.userId),
    }))
    .sort((a, b) => b.scanCount - a.scanCount || String(a.nama).localeCompare(String(b.nama)));

  const incidents = incidentsResult.results ?? [];
  const sosEvents = sosResult.results ?? [];
  const urgentIncidents = incidents.filter((row) => row.severity === 'urgent').length;
  const openIncidents = incidents.filter((row) => row.status !== 'resolved').length;

  return json({
    generatedAt: now.toISOString(),
    period: { from, to, mode },
    summary: {
      patrolUsers: guardActivity.length,
      complete: completeSessions,
      completeSessions,
      alerts: missedSessions + currentAlerts,
      coverageFrom: from,
      coverageTo: to,
      coverageDate: from === to ? from : null,
      missedSessions,
      missedCheckpoints,
      scannedCheckpoints,
      dueCheckpoints,
      completedScannedCheckpoints,
      incidentCount: incidents.length,
      openIncidents,
      urgentIncidents,
      sosCount: sosEvents.length,
      sos24h: sosEvents.length,
    },
    attendanceSummary: {
      from,
      to,
      totalUsers: users.length,
      presentUsers: presentUsers.size,
      absentUsers: Math.max(0, users.length - presentUsers.size),
      attendanceDays: attendanceDays.size,
      currentlyIn,
      faceReviewRequired,
    },
    attendanceRecent: recentAttendance,
    guardActivity,
    coverageDays,
    missedDetails,
    patrols: [],
    incidents,
    sosEvents,
  });
}

function isDateKey(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function malaysiaDateKey(date) {
  const local = new Date(date.getTime() + MALAYSIA_OFFSET_MS);
  const two = (value) => String(value).padStart(2, '0');
  return `${local.getUTCFullYear()}-${two(local.getUTCMonth() + 1)}-${two(local.getUTCDate())}`;
}

function malaysiaDayBounds(dateKey) {
  if (!isDateKey(dateKey)) return null;
  const [year, month, day] = dateKey.split('-').map(Number);
  const startMs = Date.UTC(year, month - 1, day) - MALAYSIA_OFFSET_MS;
  const endMs = startMs + DAY_MS;
  return {
    startMs,
    endMs,
    startIso: new Date(startMs).toISOString(),
    endIso: new Date(endMs).toISOString(),
  };
}

async function requireMonitor(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan || '').toLowerCase();
  if (role !== 'management' && role !== 'supervisor') {
    return { response: json({ error: 'Akses pemantauan tidak dibenarkan.' }, 403) };
  }
  return auth;
}

async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  const user = await env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  return { user };
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();
  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) {
      try {
        return decodeURIComponent(value.join('='));
      } catch (_) {
        return value.join('=');
      }
    }
  }
  return null;
}

async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}
