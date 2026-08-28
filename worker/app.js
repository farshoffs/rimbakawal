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
      if (url.pathname === '/api/sos' && request.method === 'POST') {
        return createSos(request, env);
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
  if (!['Patrol', 'Management'].includes(jawatan)) {
    return json({ error: 'Jawatan mesti Patrol atau Management.' }, 400);
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
  if (!isDateKey(from) || !isDateKey(to) || from > to) {
    return json({ error: 'Julat tarikh laporan tidak sah.' }, 400);
  }

  const fromBounds = malaysiaDayBounds(from);
  const toBounds = malaysiaDayBounds(to);
  if (!fromBounds || !toBounds) return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  const daySpan = Math.ceil((toBounds.endMs - fromBounds.startMs) / 86400000);
  if (daySpan > 31) return json({ error: 'Laporan maksimum ialah 31 hari setiap kali.' }, 400);

  const [scanResult, sosResult, userResult] = await Promise.all([
    env.DB.prepare(
      `SELECT s.id, s.scanned_at, s.nfc_uid, s.session_index,
              u.nama, u.no_kad_pengenalan, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan,
              COALESCE(c.name, 'Checkpoint') AS checkpoint_name
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN departments d ON d.id = u.department_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE s.scanned_at >= ? AND s.scanned_at < ?
       ORDER BY s.scanned_at ASC`,
    ).bind(fromBounds.startIso, toBounds.endIso).all(),
    env.DB.prepare(
      `SELECT e.id, e.triggered_at, e.note, u.nama,
              COALESCE(d.name, u.jabatan) AS jabatan
       FROM sos_events e
       JOIN users u ON u.id = e.user_id
       LEFT JOIN departments d ON d.id = e.department_id
       WHERE e.triggered_at >= ? AND e.triggered_at < ?
       ORDER BY e.triggered_at ASC`,
    ).bind(fromBounds.startIso, toBounds.endIso).all(),
    env.DB.prepare('SELECT COUNT(*) AS total FROM users WHERE active = 1').first(),
  ]);

  const scans = scanResult.results ?? [];
  const sosEvents = sosResult.results ?? [];
  return json({
    from,
    to,
    generatedAt: new Date().toISOString(),
    summary: {
      activeUsers: Number(userResult?.total || 0),
      totalScans: scans.length,
      sosEvents: sosEvents.length,
    },
    scans,
    sosEvents,
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
