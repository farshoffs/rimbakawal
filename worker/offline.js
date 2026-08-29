import appWorker from './app.js';
import { sendPushToDepartment } from './push.js';

const SESSION_COOKIE = 'rk_session';
const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;
const MAX_SYNC_BATCH = 50;
const MAX_EVENT_AGE_MS = 180 * 24 * 60 * 60 * 1000;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/api/offline/bootstrap' && request.method === 'GET') {
        return offlineBootstrap(request, env);
      }
      if (url.pathname === '/api/offline/sync' && request.method === 'POST') {
        return offlineSync(request, env);
      }
      if (url.pathname === '/api/live/start' && request.method === 'POST') {
        return liveStart(request, env);
      }
      if (url.pathname === '/api/live/location' && request.method === 'POST') {
        return liveLocation(request, env);
      }
      if (url.pathname === '/api/live/end' && request.method === 'POST') {
        return liveEnd(request, env);
      }
      if (url.pathname === '/api/monitor/live-map' && request.method === 'GET') {
        return liveMap(request, env);
      }
    } catch (error) {
      console.error(JSON.stringify({
        scope: 'offline-worker',
        path: url.pathname,
        message: error instanceof Error ? error.message : String(error),
      }));
      return json({ error: 'Ralat pelayan. Sila cuba lagi.' }, 500);
    }
    return appWorker.fetch(request, env, ctx);
  },
};

async function offlineBootstrap(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const department = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes, route_order_enforced
     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,
  ).bind(auth.user.department_id).first();
  if (!department) return json({ error: 'Jabatan tidak aktif.' }, 409);

  const checkpointsResult = await env.DB.prepare(
    `SELECT id, name, nfc_uid, position, job_instruction
     FROM checkpoints
     WHERE department_id = ? AND active = 1
     ORDER BY position ASC, id ASC`,
  ).bind(auth.user.department_id).all();

  return json({
    generatedAt: new Date().toISOString(),
    user: publicUser(auth.user),
    department: {
      id: Number(department.id),
      name: department.name,
      sessionIntervalMinutes: Number(department.session_interval_minutes || 120),
      sessionStartMinutes: Number(department.session_start_minutes ?? 420),
      routeOrderEnforced: Boolean(department.route_order_enforced),
    },
    checkpoints: (checkpointsResult.results ?? []).map((row) => ({
      id: Number(row.id),
      name: row.name,
      nfcUid: row.nfc_uid,
      position: Number(row.position),
      instruction: row.job_instruction || null,
    })),
    syncPolicy: {
      localFirst: true,
      batchSize: MAX_SYNC_BATCH,
      liveLocationBypassesQueue: true,
    },
  });
}

async function offlineSync(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const events = Array.isArray(body.events) ? body.events.slice(0, MAX_SYNC_BATCH) : [];
  if (events.length === 0) return json({ results: [], syncedAt: new Date().toISOString() });

  const results = [];
  for (const event of events) {
    const clientEventId = cleanId(event?.id);
    const type = String(event?.type ?? '').trim().toLowerCase();
    const occurredAt = parseOccurredAt(event?.occurredAt);
    if (!clientEventId || !type || !occurredAt) {
      results.push({
        id: clientEventId || String(event?.id ?? ''),
        status: 'rejected',
        error: 'Rekod tempatan tidak sah.',
      });
      continue;
    }

    const existing = await env.DB.prepare(
      `SELECT result_json FROM offline_event_receipts
       WHERE client_event_id = ? AND user_id = ? LIMIT 1`,
    ).bind(clientEventId, auth.user.id).first();
    if (existing) {
      results.push({
        id: clientEventId,
        status: 'synced',
        duplicate: true,
        result: safeJson(existing.result_json),
      });
      continue;
    }

    try {
      const payload = event?.payload && typeof event.payload === 'object' ? event.payload : {};
      let result;
      switch (type) {
        case 'scan':
          result = await syncScan(env, auth.user, clientEventId, occurredAt, payload);
          break;
        case 'incident':
          result = await syncIncident(env, auth.user, clientEventId, occurredAt, payload);
          break;
        case 'sos':
          result = await syncSos(env, auth.user, clientEventId, occurredAt, payload);
          break;
        case 'patrol_start':
        case 'patrol_end':
          result = await syncPatrolActivity(env, auth.user, clientEventId, occurredAt, type, payload);
          break;
        case 'welfare_check':
          result = await syncWelfareCheck(env, auth.user, clientEventId, occurredAt, payload);
          break;
        default:
          throw new SyncError('Jenis rekod tidak disokong.');
      }

      const resultJson = JSON.stringify(result ?? {});
      await env.DB.prepare(
        `INSERT INTO offline_event_receipts
          (client_event_id, user_id, event_type, occurred_at, synced_at, result_json)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).bind(
        clientEventId,
        auth.user.id,
        type,
        occurredAt.toISOString(),
        new Date().toISOString(),
        resultJson,
      ).run();

      const location = normalizeLocation(event?.location);
      if (location) {
        await env.DB.prepare(
          `INSERT OR REPLACE INTO field_event_locations
            (client_event_id, user_id, latitude, longitude, accuracy, recorded_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
        ).bind(
          clientEventId,
          auth.user.id,
          location.latitude,
          location.longitude,
          location.accuracy,
          occurredAt.toISOString(),
        ).run();
      }

      results.push({ id: clientEventId, status: 'synced', result });
    } catch (error) {
      results.push({
        id: clientEventId,
        status: 'rejected',
        error: error instanceof SyncError ? error.message : 'Rekod gagal diproses.',
      });
    }
  }

  return json({ results, syncedAt: new Date().toISOString() });
}

async function syncScan(env, user, clientEventId, occurredAt, payload) {
  if (!user.department_id) throw new SyncError('Jabatan pengguna tidak ditetapkan.');
  const uid = normalizeUid(payload.nfcUid);
  if (!uid || uid.length > 128) throw new SyncError('UID NFC tidak sah.');

  const department = await env.DB.prepare(
    `SELECT id, session_interval_minutes, session_start_minutes, route_order_enforced
     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,
  ).bind(user.department_id).first();
  if (!department) throw new SyncError('Jabatan tidak aktif.');

  const checkpoint = await env.DB.prepare(
    `SELECT id, name, position
     FROM checkpoints
     WHERE department_id = ? AND UPPER(nfc_uid) = UPPER(?) AND active = 1
     LIMIT 1`,
  ).bind(user.department_id, uid).first();
  if (!checkpoint) throw new SyncError('NFC tidak berdaftar untuk Jabatan ini.');

  const interval = Number(department.session_interval_minutes || 120);
  const window = sessionWindow(occurredAt, interval, department.session_start_minutes);
  const sessionIndex = window.index;
  const startMs = window.startMs;
  const endMs = window.endMs;
  const startIso = new Date(startMs).toISOString();
  const endIso = new Date(endMs).toISOString();

  const scannedResult = await env.DB.prepare(
    `SELECT DISTINCT checkpoint_id FROM nfc_scans
     WHERE user_id = ? AND scanned_at >= ? AND scanned_at < ? AND checkpoint_id IS NOT NULL`,
  ).bind(user.id, startIso, endIso).all();
  const scannedIds = new Set((scannedResult.results ?? []).map((row) => Number(row.checkpoint_id)));
  if (scannedIds.has(Number(checkpoint.id))) {
    throw new SyncError(`${checkpoint.name} sudah direkod dalam sesi ini.`);
  }

  if (Boolean(department.route_order_enforced)) {
    const routeResult = await env.DB.prepare(
      `SELECT id, name FROM checkpoints
       WHERE department_id = ? AND active = 1
       ORDER BY position ASC, id ASC`,
    ).bind(user.department_id).all();
    const next = (routeResult.results ?? []).find((row) => !scannedIds.has(Number(row.id)));
    if (next && Number(next.id) !== Number(checkpoint.id)) {
      throw new SyncError(`Titik pemeriksaan seterusnya ialah ${next.name}.`);
    }
  }

  const insert = await env.DB.prepare(
    `INSERT INTO nfc_scans (user_id, nfc_uid, scanned_at, checkpoint_id, session_index)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(
    user.id,
    uid,
    occurredAt.toISOString(),
    Number(checkpoint.id),
    sessionIndex,
  ).run();

  return {
    serverId: Number(insert.meta?.last_row_id || 0),
    clientEventId,
    checkpointId: Number(checkpoint.id),
    checkpointName: checkpoint.name,
    sessionIndex,
  };
}

async function syncIncident(env, user, clientEventId, occurredAt, payload) {
  const category = String(payload.category ?? 'Lain-lain').trim().slice(0, 80);
  const severity = String(payload.severity ?? 'normal').trim().toLowerCase();
  const note = String(payload.note ?? '').trim().slice(0, 1000);
  const checkpointId = Number(payload.checkpointId || 0) || null;
  const images = Array.isArray(payload.images) ? payload.images.slice(0, 4) : [];
  if (!note) throw new SyncError('Catatan insiden diperlukan.');
  if (!['normal', 'important', 'urgent'].includes(severity)) {
    throw new SyncError('Keutamaan insiden tidak sah.');
  }

  if (checkpointId != null) {
    const checkpoint = await env.DB.prepare(
      `SELECT id FROM checkpoints WHERE id = ? AND department_id = ? LIMIT 1`,
    ).bind(checkpointId, user.department_id).first();
    if (!checkpoint) throw new SyncError('Titik pemeriksaan insiden tidak sah.');
  }

  const insert = await env.DB.prepare(
    `INSERT INTO incident_reports
      (user_id, department_id, checkpoint_id, category, severity, note, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'open', ?)`,
  ).bind(
    user.id,
    user.department_id ?? null,
    checkpointId,
    category,
    severity,
    note,
    occurredAt.toISOString(),
  ).run();
  const incidentId = Number(insert.meta?.last_row_id || 0);

  for (const image of images) {
    const value = String(image ?? '');
    if (!/^data:image\/(jpeg|png|webp);base64,/i.test(value) || value.length > 700000) continue;
    await env.DB.prepare(
      `INSERT INTO incident_images (incident_id, image_data, created_at)
       VALUES (?, ?, ?)`,
    ).bind(incidentId, value, occurredAt.toISOString()).run();
  }

  try {
    await sendPushToDepartment(env, user.department_id, {
      title: severity === 'urgent' ? 'INSIDEN SEGERA' : severity === 'important' ? 'Insiden Penting' : 'Insiden Baru',
      body: `${user.nama} • ${category}: ${note.slice(0, 180)}`,
      kind: severity === 'urgent' ? 'incident_urgent' : 'incident',
      data: { incidentId, severity, category },
      roles: ['management', 'supervisor'],
      excludeUserId: user.id,
    });
  } catch (error) {
    console.error('Incident push failed', error);
  }

  return { serverId: incidentId, clientEventId };
}

async function syncSos(env, user, clientEventId, occurredAt, payload) {
  const note = String(payload.note ?? '').trim().slice(0, 300);
  const insert = await env.DB.prepare(
    `INSERT INTO sos_events (user_id, department_id, triggered_at, note)
     VALUES (?, ?, ?, ?)`,
  ).bind(
    user.id,
    user.department_id ?? null,
    occurredAt.toISOString(),
    note || null,
  ).run();
  const sosId = Number(insert.meta?.last_row_id || 0);
  try {
    await sendPushToDepartment(env, user.department_id, {
      title: 'SOS RimbaKawal',
      body: `${user.nama} mencetuskan SOS${note ? ` • ${note}` : ''}`.slice(0, 240),
      kind: 'sos',
      data: { sosId },
      excludeUserId: user.id,
    });
  } catch (error) {
    console.error('SOS push failed', error);
  }
  return { serverId: sosId, clientEventId };
}

async function syncPatrolActivity(env, user, clientEventId, occurredAt, type, payload) {
  const clientSessionId = cleanId(payload.clientSessionId);
  if (!clientSessionId) throw new SyncError('ID sesi tempatan tidak sah.');
  const eventType = type === 'patrol_start' ? 'start' : 'end';
  const insert = await env.DB.prepare(
    `INSERT INTO patrol_activity_log
      (client_event_id, client_session_id, user_id, department_id, event_type, occurred_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(
    clientEventId,
    clientSessionId,
    user.id,
    user.department_id ?? null,
    eventType,
    occurredAt.toISOString(),
  ).run();
  return { serverId: Number(insert.meta?.last_row_id || 0), clientEventId };
}

async function syncWelfareCheck(env, user, clientEventId, occurredAt, payload) {
  const status = String(payload.status ?? 'ok').trim().toLowerCase();
  const note = String(payload.note ?? '').trim().slice(0, 300);
  if (!['ok', 'needs_attention'].includes(status)) {
    throw new SyncError('Status kebajikan tidak sah.');
  }
  const insert = await env.DB.prepare(
    `INSERT INTO welfare_checks
      (client_event_id, user_id, department_id, status, note, checked_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(
    clientEventId,
    user.id,
    user.department_id ?? null,
    status,
    note || null,
    occurredAt.toISOString(),
  ).run();
  const welfareId = Number(insert.meta?.last_row_id || 0);
  if (status === 'needs_attention') {
    try {
      await sendPushToDepartment(env, user.department_id, {
        title: 'Kebajikan Perlu Perhatian',
        body: `${user.nama} memerlukan perhatian${note ? ` • ${note}` : ''}`.slice(0, 240),
        kind: 'welfare_attention',
        data: { welfareId },
        roles: ['management', 'supervisor'],
        excludeUserId: user.id,
      });
    } catch (error) {
      console.error('Welfare push failed', error);
    }
  }
  return { serverId: welfareId, clientEventId };
}

async function liveStart(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const clientSessionId = cleanId(body.clientSessionId);
  const startedAt = parseOccurredAt(body.startedAt) ?? new Date();
  if (!clientSessionId) return json({ error: 'ID sesi rondaan tidak sah.' }, 400);

  const nowIso = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO live_patrol_presence
      (user_id, department_id, client_session_id, started_at, active, updated_at)
     VALUES (?, ?, ?, ?, 1, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       department_id = excluded.department_id,
       client_session_id = excluded.client_session_id,
       started_at = excluded.started_at,
       ended_at = NULL,
       active = 1,
       last_latitude = NULL,
       last_longitude = NULL,
       last_accuracy = NULL,
       last_location_at = NULL,
       updated_at = excluded.updated_at`,
  ).bind(
    auth.user.id,
    auth.user.department_id ?? null,
    clientSessionId,
    startedAt.toISOString(),
    nowIso,
  ).run();

  return json({ ok: true, clientSessionId, startedAt: startedAt.toISOString() });
}

async function liveLocation(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const clientSessionId = cleanId(body.clientSessionId);
  const latitude = Number(body.latitude);
  const longitude = Number(body.longitude);
  const accuracy = Math.max(0, Number(body.accuracy || 0));
  if (!clientSessionId || !validCoordinates(latitude, longitude)) {
    return json({ error: 'Data lokasi tidak sah.' }, 400);
  }

  const recordedAt = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO live_patrol_presence
      (user_id, department_id, client_session_id, started_at, active,
       last_latitude, last_longitude, last_accuracy, last_location_at, updated_at)
     VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       department_id = excluded.department_id,
       client_session_id = excluded.client_session_id,
       active = 1,
       ended_at = NULL,
       last_latitude = excluded.last_latitude,
       last_longitude = excluded.last_longitude,
       last_accuracy = excluded.last_accuracy,
       last_location_at = excluded.last_location_at,
       updated_at = excluded.updated_at`,
  ).bind(
    auth.user.id,
    auth.user.department_id ?? null,
    clientSessionId,
    recordedAt,
    latitude,
    longitude,
    accuracy,
    recordedAt,
    recordedAt,
  ).run();

  await env.DB.prepare(
    `INSERT INTO live_patrol_trail
      (user_id, department_id, client_session_id, latitude, longitude, accuracy, recorded_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    auth.user.id,
    auth.user.department_id ?? null,
    clientSessionId,
    latitude,
    longitude,
    accuracy,
    recordedAt,
  ).run();

  return json({ ok: true, recordedAt });
}

async function liveEnd(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const clientSessionId = cleanId(body.clientSessionId);
  if (!clientSessionId) return json({ error: 'ID sesi rondaan tidak sah.' }, 400);
  const endedAt = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE live_patrol_presence
     SET active = 0, ended_at = ?, updated_at = ?
     WHERE user_id = ? AND client_session_id = ?`,
  ).bind(endedAt, endedAt, auth.user.id, clientSessionId).run();
  return json({ ok: true, endedAt });
}

async function liveMap(request, env) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  const now = new Date();
  const trailSince = new Date(now.getTime() - 60 * 60 * 1000).toISOString();

  const [presenceResult, trailResult] = await Promise.all([
    env.DB.prepare(
      `SELECT p.user_id, p.department_id, p.client_session_id, p.started_at,
              p.last_latitude, p.last_longitude, p.last_accuracy, p.last_location_at,
              u.nama, u.profile_picture, COALESCE(d.name, u.jabatan) AS jabatan
       FROM live_patrol_presence p
       JOIN users u ON u.id = p.user_id
       LEFT JOIN departments d ON d.id = p.department_id
       WHERE p.active = 1 AND u.active = 1
       ORDER BY p.updated_at DESC`,
    ).all(),
    env.DB.prepare(
      `SELECT user_id, client_session_id, latitude, longitude, accuracy, recorded_at
       FROM live_patrol_trail
       WHERE recorded_at >= ?
       ORDER BY user_id ASC, recorded_at ASC`,
    ).bind(trailSince).all(),
  ]);

  const trailsByUser = new Map();
  for (const row of trailResult.results ?? []) {
    const key = Number(row.user_id);
    const list = trailsByUser.get(key) ?? [];
    list.push({
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      accuracy: row.accuracy == null ? null : Number(row.accuracy),
      recordedAt: row.recorded_at,
    });
    if (list.length > 60) list.shift();
    trailsByUser.set(key, list);
  }

  const patrols = (presenceResult.results ?? []).map((row) => {
    const locationAt = row.last_location_at ? new Date(row.last_location_at) : null;
    const ageSeconds = locationAt ? Math.max(0, Math.floor((now.getTime() - locationAt.getTime()) / 1000)) : null;
    return {
      userId: Number(row.user_id),
      nama: row.nama,
      jabatan: row.jabatan,
      profilePicture: row.profile_picture,
      clientSessionId: row.client_session_id,
      startedAt: row.started_at,
      latitude: row.last_latitude == null ? null : Number(row.last_latitude),
      longitude: row.last_longitude == null ? null : Number(row.last_longitude),
      accuracy: row.last_accuracy == null ? null : Number(row.last_accuracy),
      locationAt: row.last_location_at,
      locationAgeSeconds: ageSeconds,
      liveState: ageSeconds == null ? 'waiting_gps' : ageSeconds <= 45 ? 'live' : ageSeconds <= 180 ? 'delayed' : 'stale',
      trail: trailsByUser.get(Number(row.user_id)) ?? [],
    };
  });

  return json({ generatedAt: now.toISOString(), patrols });
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
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
            COALESCE(d.session_start_minutes, 420) AS session_start_minutes
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN departments d ON d.id = u.department_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  return { user };
}

function publicUser(user) {
  return {
    id: Number(user.id),
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.jabatan,
    active: Boolean(user.active),
    departmentId: user.department_id == null ? null : Number(user.department_id),
    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),
    sessionStartMinutes: Number(user.session_start_minutes ?? 420),
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

function cleanId(value) {
  const id = String(value ?? '').trim();
  return /^[A-Za-z0-9._:-]{8,120}$/.test(id) ? id : null;
}

function parseOccurredAt(value) {
  const date = new Date(String(value ?? ''));
  if (Number.isNaN(date.getTime())) return null;
  const now = Date.now();
  if (date.getTime() > now + 10 * 60 * 1000) return null;
  if (date.getTime() < now - MAX_EVENT_AGE_MS) return null;
  return date;
}

function normalizeLocation(value) {
  if (!value || typeof value !== 'object') return null;
  const latitude = Number(value.latitude);
  const longitude = Number(value.longitude);
  if (!validCoordinates(latitude, longitude)) return null;
  return {
    latitude,
    longitude,
    accuracy: Math.max(0, Number(value.accuracy || 0)),
  };
}

function validCoordinates(latitude, longitude) {
  return Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
    Number.isFinite(longitude) && longitude >= -180 && longitude <= 180;
}

function normalizeUid(value) {
  return String(value ?? '').trim().toUpperCase().replace(/\s+/g, '');
}

function scheduleDayWindow(value, startMinutes = 420) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const safeStart = Math.max(0, Math.min(1439, Number(startMinutes ?? 420)));
  const localMidnightUtc = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
  let startMs = localMidnightUtc - MALAYSIA_OFFSET_MS + safeStart * 60000;
  if (minuteOfDay < safeStart) startMs -= 86400000;
  return { startMs, endMs: startMs + 86400000 };
}

function sessionWindow(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  const index = Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
  const startMs = day.startMs + index * safeInterval * 60000;
  return { index, startMs, endMs: Math.min(day.endMs, startMs + safeInterval * 60000) };
}

function currentSessionIndex(value, interval, startMinutes = 420) {
  return sessionWindow(value, interval, startMinutes).index;
}

function malaysiaDateKey(value) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const two = (number) => String(number).padStart(2, '0');
  return `${shifted.getUTCFullYear()}-${two(shifted.getUTCMonth() + 1)}-${two(shifted.getUTCDate())}`;
}

function malaysiaDayBounds(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return null;
  const startMs = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) - MALAYSIA_OFFSET_MS;
  return {
    startMs,
    endMs: startMs + 86400000,
  };
}

async function readJson(request) {
  try { return await request.json(); } catch (_) { return {}; }
}

async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function safeJson(value) {
  try { return value ? JSON.parse(value) : {}; } catch (_) { return {}; }
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

class SyncError extends Error {}
