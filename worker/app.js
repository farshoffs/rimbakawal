import baseWorker from './index.js';

const SESSION_COOKIE = 'rk_session';
const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    try {
      if (url.pathname === '/api/admin/users' && request.method === 'POST') {
        return createUser(request, env);
      }
      if (url.pathname === '/api/admin/reports' && request.method === 'GET') {
        return adminReport(request, env, url);
      }
      if (url.pathname === '/api/admin/command-center' && request.method === 'GET') {
        return commandCenter(request, env);
      }
      if (url.pathname === '/api/sos' && request.method === 'POST') {
        return createSos(request, env);
      }
      if (url.pathname === '/api/incidents' && request.method === 'POST') {
        return createIncident(request, env);
      }
      if (url.pathname === '/api/patrol/config' && request.method === 'GET') {
        return smartPatrolConfig(request, env);
      }
      if (url.pathname === '/api/patrol/start' && request.method === 'POST') {
        return startPatrolSession(request, env);
      }
      if (url.pathname === '/api/patrol/location' && request.method === 'POST') {
        return updatePatrolLocation(request, env);
      }
      if (url.pathname === '/api/patrol/end' && request.method === 'POST') {
        return endPatrolSession(request, env);
      }
      if (url.pathname === '/api/scans' && request.method === 'POST') {
        return createSmartScan(request, env);
      }

      const incidentMatch = url.pathname.match(/^\/api\/admin\/incidents\/(\d+)\/status$/);
      if (incidentMatch && request.method === 'PUT') {
        return updateIncidentStatus(request, env, Number(incidentMatch[1]));
      }
      const incidentImagesMatch = url.pathname.match(/^\/api\/admin\/incidents\/(\d+)\/images$/);
      if (incidentImagesMatch && request.method === 'GET') {
        return getIncidentImages(request, env, Number(incidentImagesMatch[1]));
      }
    } catch (error) {
      console.error(error);
      return json({ error: 'Ralat pelayan. Sila cuba lagi.' }, 500);
    }

    return baseWorker.fetch(request, env, ctx);
  },
};

async function createUser(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const nama = String(body.nama ?? '').trim().toUpperCase();
  const identityCard = String(body.noKadPengenalan ?? '').replace(/\D/g, '');
  const jawatan = String(body.jawatan ?? 'Patrol').trim();
  const departmentId = Number(body.departmentId ?? 0);

  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!/^\d{12}$/.test(identityCard)) {
    return json({ error: 'No. Kad Pengenalan mesti mengandungi 12 digit.' }, 400);
  }
  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {
    return json({ error: 'Jawatan mesti Patrol, Supervisor atau Management.' }, 400);
  }
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Pilih Jabatan pengguna.' }, 400);
  }

  const department = await env.DB.prepare(
    'SELECT id, name, session_interval_minutes FROM departments WHERE id = ? AND active = 1 LIMIT 1',
  ).bind(departmentId).first();
  if (!department) return json({ error: 'Jabatan tidak ditemui atau tidak aktif.' }, 404);

  const duplicate = await env.DB.prepare(
    'SELECT id FROM users WHERE no_kad_pengenalan = ? LIMIT 1',
  ).bind(identityCard).first();
  if (duplicate) return json({ error: 'No. Kad Pengenalan ini sudah berdaftar.' }, 409);

  const result = await env.DB.prepare(
    `INSERT INTO users (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, active, department_id)
     VALUES (?, ?, ?, NULL, ?, 1, ?)`,
  ).bind(nama, identityCard, jawatan, department.name, departmentId).run();

  const user = await getUserById(env, result.meta?.last_row_id);
  return json({ user: publicUser(user) }, 201);
}

async function startPatrolSession(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const now = new Date();
  const startedAt = now.toISOString();
  const interval = Number(auth.user.session_interval_minutes || 120);
  const sessionIndex = currentSessionIndex(now, interval);
  await env.DB.prepare(
    `UPDATE patrol_sessions
     SET status = 'ended', ended_at = COALESCE(ended_at, ?)
     WHERE user_id = ? AND status = 'active'`,
  ).bind(startedAt, auth.user.id).run();

  const result = await env.DB.prepare(
    `INSERT INTO patrol_sessions
      (user_id, department_id, session_index, started_at, status)
     VALUES (?, ?, ?, ?, 'active')`,
  ).bind(auth.user.id, auth.user.department_id, sessionIndex, startedAt).run();

  return json({
    patrolSession: {
      id: Number(result.meta?.last_row_id),
      sessionIndex,
      startedAt,
    },
  }, 201);
}

async function updatePatrolLocation(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const patrolSessionId = Number(body.patrolSessionId);
  const latitude = Number(body.latitude);
  const longitude = Number(body.longitude);
  const accuracy = Math.max(0, Number(body.accuracy || 0));
  if (!Number.isInteger(patrolSessionId) || patrolSessionId <= 0 ||
      !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return json({ error: 'Data lokasi tidak sah.' }, 400);
  }

  const locationAt = new Date().toISOString();
  const result = await env.DB.prepare(
    `UPDATE patrol_sessions
     SET last_latitude = ?, last_longitude = ?, last_accuracy = ?,
         last_location_at = ?
     WHERE id = ? AND user_id = ? AND status = 'active'`,
  ).bind(
    latitude,
    longitude,
    accuracy,
    locationAt,
    patrolSessionId,
    auth.user.id,
  ).run();
  if (Number(result.meta?.changes || 0) === 0) {
    return json({ error: 'Sesi Rondaan aktif tidak ditemui.' }, 404);
  }
  return json({ ok: true, locationAt });
}

async function endPatrolSession(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const patrolSessionId = Number(body.patrolSessionId);
  if (!Number.isInteger(patrolSessionId) || patrolSessionId <= 0) {
    return json({ error: 'Sesi Rondaan tidak sah.' }, 400);
  }
  const endedAt = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE patrol_sessions
     SET status = 'ended', ended_at = ?
     WHERE id = ? AND user_id = ? AND status = 'active'`,
  ).bind(endedAt, patrolSessionId, auth.user.id).run();
  return json({ ok: true, endedAt });
}

async function smartPatrolConfig(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const department = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, route_order_enforced
     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,
  ).bind(auth.user.department_id).first();
  if (!department) return json({ error: 'Jabatan tidak aktif.' }, 409);

  const result = await env.DB.prepare(
    `SELECT id, name, position, job_instruction
     FROM checkpoints
     WHERE department_id = ? AND active = 1
     ORDER BY position ASC, id ASC`,
  ).bind(auth.user.department_id).all();
  const checkpoints = result.results ?? [];

  const interval = Number(department.session_interval_minutes || 120);
  const now = new Date();
  const day = malaysiaDayBounds(malaysiaDateKey(now));
  const sessionIndex = currentSessionIndex(now, interval);
  const sessionStart = day.startMs + sessionIndex * interval * 60000;
  const sessionEnd = Math.min(day.endMs, sessionStart + interval * 60000);

  const scanned = await env.DB.prepare(
    `SELECT DISTINCT checkpoint_id FROM nfc_scans
     WHERE user_id = ? AND scanned_at >= ? AND scanned_at < ? AND checkpoint_id IS NOT NULL`,
  ).bind(auth.user.id, new Date(sessionStart).toISOString(), new Date(sessionEnd).toISOString()).all();
  const scannedIds = new Set((scanned.results ?? []).map((row) => Number(row.checkpoint_id)));
  const nextCheckpoint = checkpoints.find((row) => !scannedIds.has(Number(row.id))) ?? null;

  return json({
    department: {
      id: Number(department.id),
      name: department.name,
      sessionIntervalMinutes: interval,
      routeOrderEnforced: Boolean(department.route_order_enforced),
    },
    sessionIndex,
    sessionStartAt: new Date(sessionStart).toISOString(),
    sessionEndAt: new Date(sessionEnd).toISOString(),
    checkpoints: checkpoints.map((row) => ({
      id: Number(row.id),
      name: row.name,
      position: Number(row.position),
      instruction: row.job_instruction || null,
      completed: scannedIds.has(Number(row.id)),
    })),
    nextCheckpoint: nextCheckpoint ? {
      id: Number(nextCheckpoint.id),
      name: nextCheckpoint.name,
      position: Number(nextCheckpoint.position),
      instruction: nextCheckpoint.job_instruction || null,
    } : null,
  });
}

async function createSmartScan(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const body = await readJson(request);
  const nfcUid = normalizeUid(body.nfcUid);
  if (!nfcUid || nfcUid.length > 128) {
    return json({ error: 'UID NFC tidak sah.' }, 400);
  }

  const department = await env.DB.prepare(
    `SELECT id, session_interval_minutes, route_order_enforced
     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,
  ).bind(auth.user.department_id).first();
  if (!department) return json({ error: 'Jabatan tidak aktif.' }, 409);

  const checkpoint = await env.DB.prepare(
    `SELECT id, name, position, job_instruction
     FROM checkpoints
     WHERE department_id = ? AND UPPER(nfc_uid) = UPPER(?) AND active = 1
     LIMIT 1`,
  ).bind(auth.user.department_id, nfcUid).first();
  if (!checkpoint) {
    return json({ error: 'NFC ini tidak berdaftar sebagai checkpoint untuk Jabatan anda.' }, 403);
  }

  const now = new Date();
  const scannedAt = now.toISOString();
  const interval = Number(department.session_interval_minutes || 120);
  const day = malaysiaDayBounds(malaysiaDateKey(now));
  const sessionIndex = currentSessionIndex(now, interval);
  const sessionStart = day.startMs + sessionIndex * interval * 60000;
  const sessionEnd = Math.min(day.endMs, sessionStart + interval * 60000);

  const activeResult = await env.DB.prepare(
    `SELECT id, name, position FROM checkpoints
     WHERE department_id = ? AND active = 1
     ORDER BY position ASC, id ASC`,
  ).bind(auth.user.department_id).all();
  const activeCheckpoints = activeResult.results ?? [];

  const scannedResult = await env.DB.prepare(
    `SELECT DISTINCT checkpoint_id FROM nfc_scans
     WHERE user_id = ? AND scanned_at >= ? AND scanned_at < ? AND checkpoint_id IS NOT NULL`,
  ).bind(auth.user.id, new Date(sessionStart).toISOString(), new Date(sessionEnd).toISOString()).all();
  const scannedIds = new Set((scannedResult.results ?? []).map((row) => Number(row.checkpoint_id)));

  if (scannedIds.has(Number(checkpoint.id))) {
    return json({ error: `${checkpoint.name} telah direkodkan dalam sesi ini.` }, 409);
  }

  if (Boolean(department.route_order_enforced)) {
    const expected = activeCheckpoints.find((row) => !scannedIds.has(Number(row.id)));
    if (expected && Number(expected.id) !== Number(checkpoint.id)) {
      return json({
        error: `Susunan rondaan aktif. Checkpoint seterusnya ialah ${expected.name}.`,
        expectedCheckpoint: {
          id: Number(expected.id),
          name: expected.name,
          position: Number(expected.position),
        },
      }, 409);
    }
  }

  const result = await env.DB.prepare(
    `INSERT INTO nfc_scans (user_id, nfc_uid, scanned_at, checkpoint_id, session_index)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(auth.user.id, nfcUid, scannedAt, checkpoint.id, sessionIndex).run();

  const next = activeCheckpoints.find((row) =>
    Number(row.id) !== Number(checkpoint.id) &&
    !scannedIds.has(Number(row.id)) &&
    Number(row.position) > Number(checkpoint.position)
  ) ?? null;

  return json({
    scan: {
      id: result.meta?.last_row_id ?? null,
      nfc_uid: nfcUid,
      scanned_at: scannedAt,
      checkpoint_id: checkpoint.id,
      checkpoint_name: checkpoint.name,
      session_index: sessionIndex,
    },
    nextCheckpoint: next ? {
      id: Number(next.id),
      name: next.name,
      position: Number(next.position),
    } : null,
    sessionComplete: scannedIds.size + 1 >= activeCheckpoints.length,
  }, 201);
}

async function createIncident(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const checkpointId = Number(body.checkpointId ?? 0) || null;
  const category = String(body.category ?? 'Lain-lain').trim().slice(0, 60);
  const severity = String(body.severity ?? 'normal').trim().toLowerCase();
  const note = String(body.note ?? '').trim().slice(0, 500);
  const images = Array.isArray(body.images) ? body.images : [];

  if (!note) return json({ error: 'Masukkan catatan insiden.' }, 400);
  if (!['normal', 'important', 'urgent'].includes(severity)) {
    return json({ error: 'Tahap insiden tidak sah.' }, 400);
  }
  if (images.length > 4) {
    return json({ error: 'Maksimum 4 gambar bagi setiap laporan.' }, 400);
  }
  const validImages = images.map((value) => String(value ?? '').trim());
  if (validImages.some((value) =>
    !/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/i.test(value) || value.length > 500000
  )) {
    return json({ error: 'Format atau saiz gambar tidak sah.' }, 400);
  }

  if (checkpointId) {
    const checkpoint = await env.DB.prepare(
      'SELECT id FROM checkpoints WHERE id = ? AND department_id = ? LIMIT 1',
    ).bind(checkpointId, auth.user.department_id).first();
    if (!checkpoint) return json({ error: 'Checkpoint tidak sah untuk Jabatan anda.' }, 400);
  }

  const createdAt = new Date().toISOString();
  const result = await env.DB.prepare(
    `INSERT INTO incident_reports
      (user_id, department_id, checkpoint_id, category, severity, note, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'open', ?)`,
  ).bind(
    auth.user.id,
    auth.user.department_id ?? null,
    checkpointId,
    category || 'Lain-lain',
    severity,
    note,
    createdAt,
  ).run();

  const incidentId = Number(result.meta?.last_row_id);
  if (validImages.length > 0) {
    await env.DB.batch(validImages.map((image) => env.DB.prepare(
      `INSERT INTO incident_images (incident_id, image_data, created_at)
       VALUES (?, ?, ?)`,
    ).bind(incidentId, image, createdAt)));
  }

  return json({
    incident: {
      id: incidentId || null,
      category,
      severity,
      note,
      status: 'open',
      createdAt,
      imageCount: validImages.length,
    },
  }, 201);
}

async function getIncidentImages(request, env, incidentId) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(incidentId) || incidentId <= 0) {
    return json({ error: 'Insiden tidak sah.' }, 400);
  }
  const incident = await env.DB.prepare(
    'SELECT id FROM incident_reports WHERE id = ? LIMIT 1',
  ).bind(incidentId).first();
  if (!incident) return json({ error: 'Insiden tidak ditemui.' }, 404);

  const result = await env.DB.prepare(
    `SELECT image_data
     FROM incident_images WHERE incident_id = ? ORDER BY id ASC`,
  ).bind(incidentId).all();
  return json({
    images: (result.results ?? []).map((row) => row.image_data),
  });
}

async function updateIncidentStatus(request, env, incidentId) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const status = String(body.status ?? '').trim().toLowerCase();
  if (!['open', 'acknowledged', 'resolved'].includes(status)) {
    return json({ error: 'Status insiden tidak sah.' }, 400);
  }

  const existing = await env.DB.prepare('SELECT id FROM incident_reports WHERE id = ? LIMIT 1')
    .bind(incidentId).first();
  if (!existing) return json({ error: 'Insiden tidak ditemui.' }, 404);

  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE incident_reports
     SET status = ?,
         acknowledged_at = CASE WHEN ? = 'acknowledged' AND acknowledged_at IS NULL THEN ? ELSE acknowledged_at END,
         resolved_at = CASE WHEN ? = 'resolved' THEN ? ELSE resolved_at END
     WHERE id = ?`,
  ).bind(status, status, now, status, now, incidentId).run();
  return json({ ok: true, status });
}

async function commandCenter(request, env) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;

  const now = new Date();
  const today = malaysiaDateKey(now);
  const bounds = malaysiaDayBounds(today);
  const liveSince = new Date(now.getTime() - 2 * 60 * 1000).toISOString();

  const [
    usersResult,
    checkpointResult,
    scansResult,
    sosResult,
    incidentsResult,
    patrolSessionsResult,
  ] = await Promise.all([
    env.DB.prepare(
      `SELECT u.id, u.nama, u.department_id, COALESCE(d.name, u.jabatan) AS jabatan,
              u.profile_picture,
              COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes
       FROM users u
       LEFT JOIN departments d ON d.id = u.department_id
       WHERE u.active = 1 AND LOWER(u.jawatan) IN ('patrol', 'supervisor')
       ORDER BY jabatan ASC, u.nama ASC`,
    ).all(),
    env.DB.prepare(
      `SELECT department_id, COUNT(*) AS total
       FROM checkpoints WHERE active = 1 GROUP BY department_id`,
    ).all(),
    env.DB.prepare(
      `SELECT user_id, checkpoint_id, session_index, scanned_at
       FROM nfc_scans
       WHERE scanned_at >= ? AND scanned_at < ?
       ORDER BY scanned_at ASC`,
    ).bind(bounds.startIso, bounds.endIso).all(),
    env.DB.prepare(
      `SELECT e.id, e.triggered_at, e.note, u.nama, COALESCE(d.name, u.jabatan) AS jabatan
       FROM sos_events e
       JOIN users u ON u.id = e.user_id
       LEFT JOIN departments d ON d.id = e.department_id
       WHERE e.triggered_at >= ?
       ORDER BY e.triggered_at DESC LIMIT 10`,
    ).bind(new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()).all(),
    env.DB.prepare(
      `SELECT i.id, i.category, i.severity, i.note, i.status, i.created_at,
              u.nama, COALESCE(d.name, u.jabatan) AS jabatan,
              c.name AS checkpoint_name,
              (SELECT COUNT(*) FROM incident_images ii WHERE ii.incident_id = i.id) AS image_count
       FROM incident_reports i
       JOIN users u ON u.id = i.user_id
       LEFT JOIN departments d ON d.id = i.department_id
       LEFT JOIN checkpoints c ON c.id = i.checkpoint_id
       WHERE i.status <> 'resolved'
       ORDER BY CASE i.severity WHEN 'urgent' THEN 0 WHEN 'important' THEN 1 ELSE 2 END,
                i.created_at DESC
       LIMIT 50`,
    ).all(),
    env.DB.prepare(
      `SELECT ps.id, ps.user_id, ps.started_at, ps.last_latitude, ps.last_longitude,
              ps.last_accuracy, ps.last_location_at
       FROM patrol_sessions ps
       JOIN (
         SELECT user_id, MAX(id) AS latest_id
         FROM patrol_sessions
         WHERE status = 'active'
           AND COALESCE(last_location_at, started_at) >= ?
         GROUP BY user_id
       ) latest ON latest.latest_id = ps.id`,
    ).bind(liveSince).all(),
  ]);

  const checkpointCounts = new Map(
    (checkpointResult.results ?? []).map((row) => [Number(row.department_id), Number(row.total)]),
  );
  const scans = scansResult.results ?? [];
  const activePatrols = new Map(
    (patrolSessionsResult.results ?? []).map((row) => [Number(row.user_id), row]),
  );
  const patrols = [];
  let completeCount = 0;
  let alertCount = 0;

  for (const user of usersResult.results ?? []) {
    const interval = Number(user.session_interval_minutes || 120);
    const currentIndex = currentSessionIndex(now, interval);
    const expected = checkpointCounts.get(Number(user.department_id)) ?? 0;
    const currentScans = scans.filter((row) =>
      Number(row.user_id) === Number(user.id) && Number(row.session_index) === currentIndex
    );
    const uniqueCurrent = new Set(currentScans.map((row) => Number(row.checkpoint_id)).filter((id) => id > 0));
    const lastScan = scans.filter((row) => Number(row.user_id) === Number(user.id)).at(-1) ?? null;
    const activePatrol = activePatrols.get(Number(user.id)) ?? null;

    let missedSessions = 0;
    for (let index = 0; index < currentIndex; index += 1) {
      const unique = new Set(scans
        .filter((row) => Number(row.user_id) === Number(user.id) && Number(row.session_index) === index)
        .map((row) => Number(row.checkpoint_id)).filter((id) => id > 0));
      if (expected > 0 && unique.size < expected) missedSessions += 1;
    }

    const shifted = new Date(now.getTime() + MALAYSIA_OFFSET_MS);
    const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
    const minutesIntoSession = minuteOfDay - currentIndex * interval;
    const grace = Math.max(10, Math.min(30, Math.floor(interval / 4)));

    let status = 'waiting';
    if (expected === 0) status = 'no_checkpoints';
    else if (uniqueCurrent.size >= expected) status = 'complete';
    else if (activePatrol) status = 'patrolling';
    else if (missedSessions > 0) status = 'missed';
    else if (minutesIntoSession >= grace && uniqueCurrent.size === 0) status = 'late';
    else if (uniqueCurrent.size > 0) status = 'patrolling';

    if (status === 'complete') completeCount += 1;
    if (status === 'late' || status === 'missed') alertCount += 1;

    patrols.push({
      userId: Number(user.id),
      nama: user.nama,
      jabatan: user.jabatan,
      profilePicture: user.profile_picture,
      status,
      sessionIndex: currentIndex,
      scannedCount: uniqueCurrent.size,
      expectedCount: expected,
      missedSessions,
      lastScanAt: lastScan?.scanned_at ?? null,
      patrolSessionId: activePatrol ? Number(activePatrol.id) : null,
      sessionStartedAt: activePatrol?.started_at ?? null,
      latitude: activePatrol?.last_latitude == null ? null : Number(activePatrol.last_latitude),
      longitude: activePatrol?.last_longitude == null ? null : Number(activePatrol.last_longitude),
      accuracy: activePatrol?.last_accuracy == null ? null : Number(activePatrol.last_accuracy),
      locationAt: activePatrol?.last_location_at ?? null,
    });
  }

  const incidents = incidentsResult.results ?? [];
  const urgentIncidents = incidents.filter((row) => row.severity === 'urgent').length;

  return json({
    generatedAt: now.toISOString(),
    summary: {
      patrolUsers: patrols.length,
      complete: completeCount,
      alerts: alertCount,
      openIncidents: incidents.length,
      urgentIncidents,
      sos24h: (sosResult.results ?? []).length,
    },
    patrols,
    incidents,
    sosEvents: sosResult.results ?? [],
  });
}

async function createSos(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const note = String(body.note ?? '').trim().slice(0, 200);
  const triggeredAt = new Date().toISOString();
  const result = await env.DB.prepare(
    `INSERT INTO sos_events (user_id, department_id, triggered_at, note)
     VALUES (?, ?, ?, ?)`,
  ).bind(auth.user.id, auth.user.department_id ?? null, triggeredAt, note || null).run();

  return json({
    event: {
      id: result.meta?.last_row_id ?? null,
      triggeredAt,
      note: note || null,
    },
  }, 201);
}

async function adminReport(request, env, url) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const today = malaysiaDateKey(new Date());
  const from = url.searchParams.get('from') || today;
  const to = url.searchParams.get('to') || today;
  const rawDepartmentId = url.searchParams.get('departmentId');
  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);
  if (!isDateKey(from) || !isDateKey(to) || from > to) {
    return json({ error: 'Julat tarikh laporan tidak sah.' }, 400);
  }
  if (departmentId != null && (!Number.isInteger(departmentId) || departmentId <= 0)) {
    return json({ error: 'Jabatan laporan tidak sah.' }, 400);
  }

  const fromBounds = malaysiaDayBounds(from);
  const toBounds = malaysiaDayBounds(to);
  if (!fromBounds || !toBounds) return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  const daySpan = Math.ceil((toBounds.endMs - fromBounds.startMs) / 86400000);
  if (daySpan > 31) return json({ error: 'Laporan maksimum ialah 31 hari setiap kali.' }, 400);

  let department = null;
  if (departmentId != null) {
    department = await env.DB.prepare(
      'SELECT id, name FROM departments WHERE id = ? LIMIT 1',
    ).bind(departmentId).first();
    if (!department) return json({ error: 'Jabatan tidak ditemui.' }, 404);
  }
  const scanSql = `SELECT s.id, s.scanned_at, s.nfc_uid, s.session_index,
              u.nama, u.no_kad_pengenalan, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan,
              COALESCE(c.name, 'Checkpoint') AS checkpoint_name
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN departments d ON d.id = u.department_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE s.scanned_at >= ? AND s.scanned_at < ?
       ${departmentId == null ? '' : 'AND u.department_id = ?'}
       ORDER BY s.scanned_at ASC`;
  const sosSql = `SELECT e.id, e.triggered_at, e.note, u.nama,
              COALESCE(d.name, u.jabatan) AS jabatan
       FROM sos_events e
       JOIN users u ON u.id = e.user_id
       LEFT JOIN departments d ON d.id = e.department_id
       WHERE e.triggered_at >= ? AND e.triggered_at < ?
       ${departmentId == null ? '' : 'AND e.department_id = ?'}
       ORDER BY e.triggered_at ASC`;
  const incidentSql = `SELECT i.id, i.category, i.severity, i.note, i.status, i.created_at,
              u.nama, COALESCE(d.name, u.jabatan) AS jabatan, c.name AS checkpoint_name
       FROM incident_reports i
       JOIN users u ON u.id = i.user_id
       LEFT JOIN departments d ON d.id = i.department_id
       LEFT JOIN checkpoints c ON c.id = i.checkpoint_id
       WHERE i.created_at >= ? AND i.created_at < ?
       ${departmentId == null ? '' : 'AND i.department_id = ?'}
       ORDER BY i.created_at ASC`;
  const dateBindings = departmentId == null
    ? [fromBounds.startIso, toBounds.endIso]
    : [fromBounds.startIso, toBounds.endIso, departmentId];
  const [scanResult, sosResult, userResult, incidentResult] = await Promise.all([
    env.DB.prepare(
      scanSql,
    ).bind(...dateBindings).all(),
    env.DB.prepare(sosSql).bind(...dateBindings).all(),
    departmentId == null
      ? env.DB.prepare('SELECT COUNT(*) AS total FROM users WHERE active = 1').first()
      : env.DB.prepare(
        'SELECT COUNT(*) AS total FROM users WHERE active = 1 AND department_id = ?',
      ).bind(departmentId).first(),
    env.DB.prepare(incidentSql).bind(...dateBindings).all(),
  ]);

  const scans = scanResult.results ?? [];
  const sosEvents = sosResult.results ?? [];
  const incidents = incidentResult.results ?? [];
  return json({
    from,
    to,
    department: department == null ? null : { id: Number(department.id), name: department.name },
    generatedAt: new Date().toISOString(),
    summary: {
      activeUsers: Number(userResult?.total || 0),
      totalScans: scans.length,
      sosEvents: sosEvents.length,
      incidents: incidents.length,
    },
    scans,
    sosEvents,
    incidents,
  });
}

async function requireManagement(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  if (String(auth.user.jawatan).toLowerCase() !== 'management') {
    return { response: json({ error: 'Akses Admin hanya untuk Management.' }, 403) };
  }
  return auth;
}

async function requireMonitor(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan).toLowerCase();
  if (role !== 'management' && role !== 'supervisor') {
    return { response: json({ error: 'Akses pemantauan hanya untuk Admin atau Supervisor.' }, 403) };
  }
  return auth;
}

async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };

  const user = await env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id,
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN departments d ON d.id = u.department_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();

  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  return { user };
}

async function getUserById(env, id) {
  return env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id,
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes
     FROM users u
     LEFT JOIN departments d ON d.id = u.department_id
     WHERE u.id = ? LIMIT 1`,
  ).bind(id).first();
}

function publicUser(user) {
  return {
    id: user.id,
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.jabatan,
    active: Boolean(user.active),
    departmentId: user.department_id == null ? null : Number(user.department_id),
    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),
  };
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();
  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) return value.join('=');
  }
  return null;
}

function normalizeUid(value) {
  return String(value ?? '').trim().toUpperCase().replace(/\s+/g, '');
}

function currentSessionIndex(value, interval) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  return Math.floor(minuteOfDay / Math.max(15, Math.min(1440, interval)));
}

async function readJson(request) {
  try { return await request.json(); } catch (_) { return {}; }
}

async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function isDateKey(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function malaysiaDateKey(value) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const two = (v) => String(v).padStart(2, '0');
  return `${shifted.getUTCFullYear()}-${two(shifted.getUTCMonth() + 1)}-${two(shifted.getUTCDate())}`;
}

function malaysiaDayBounds(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return null;
  const startMs = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) - MALAYSIA_OFFSET_MS;
  const endMs = startMs + 86400000;
  return { startMs, endMs, startIso: new Date(startMs).toISOString(), endIso: new Date(endMs).toISOString() };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
