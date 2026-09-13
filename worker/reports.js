import commandCenterWorker from './command_center_period.js';

const SESSION_COOKIE = 'rk_session';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const reportOnlyAllowed =
      (url.pathname === '/api/auth/session' && request.method === 'GET') ||
      (url.pathname === '/api/auth/logout' && request.method === 'POST') ||
      (url.pathname === '/api/admin/reports' && request.method === 'GET') ||
      (url.pathname === '/api/admin/departments' && request.method === 'GET');
    if (url.pathname.startsWith('/api/') &&
        url.pathname !== '/api/auth/login' &&
        !reportOnlyAllowed) {
      const denied = await denyAdministrationOperationalAccess(request, env);
      if (denied) return denied;
    }
    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {
      return monthlyReport(request, env, url);
    }
    return commandCenterWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    if (typeof commandCenterWorker.scheduled === 'function') {
      return commandCenterWorker.scheduled(event, env, ctx);
    }
  },
};

async function monthlyReport(request, env, url) {
  const auth = await requireReportAccess(request, env);
  if (auth.response) return auth.response;

  const from = String(url.searchParams.get('from') || '');
  const to = String(url.searchParams.get('to') || '');
  const departmentId = Number(url.searchParams.get('departmentId') || 0);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || from > to) {
    return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  }
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Pilih satu Sekolah untuk laporan PKK.' }, 400);
  }

  const departmentMeta = await env.DB.prepare(
    `SELECT d.id, d.name, d.active, d.company_id,
            COALESCE(c.name, d.company_name, '') AS company_name, d.zone
       FROM departments d
       LEFT JOIN companies c ON c.id = d.company_id
      WHERE d.id = ? LIMIT 1`,
  ).bind(departmentId).first();
  if (!departmentMeta) return json({ error: 'Sekolah tidak ditemui.' }, 404);

  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  if (role === 'administration') {
    const ownCompanyId = Number(auth.user.company_id || 0);
    if (!ownCompanyId || Number(departmentMeta.company_id || 0) !== ownCompanyId) {
      return json({ error: 'Sekolah ini bukan di bawah Syarikat akaun anda.' }, 403);
    }
  }

  const fromStart = malaysiaStartIso(from);
  const toEnd = malaysiaEndIso(to);
  const attendanceToEnd = addUtcDays(toEnd, 1);
  if (!fromStart || !toEnd || !attendanceToEnd) {
    return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  }

  const scanSql = `SELECT s.id, s.user_id, s.checkpoint_id, s.scanned_at, s.nfc_uid, s.session_index,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan,
              COALESCE(c.name, 'Checkpoint') AS checkpoint_name,
              c.position AS checkpoint_position
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN departments d ON d.id = u.department_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE s.scanned_at >= ? AND s.scanned_at < ?
         AND u.department_id = ?
       ORDER BY s.scanned_at ASC, s.session_index ASC, c.position ASC, s.id ASC`;

  // Include one extra Malaysian calendar day so a night-shift IN on the
  // last report date can be paired with its OUT on the following morning.
  const attendanceSql = `SELECT a.id, a.user_id, a.department_id, a.work_date,
              a.punch_type, a.punched_at, a.latitude, a.longitude, a.distance_m,
              a.face_status, a.face_score,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan
       FROM attendance_records a
       JOIN users u ON u.id = a.user_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE a.punched_at >= ? AND a.punched_at < ?
         AND a.department_id = ?
       ORDER BY a.user_id ASC, a.punched_at ASC, a.id ASC`;

  const [scanResult, attendanceResult, checkpointResult, guardResult] = await Promise.all([
    env.DB.prepare(scanSql).bind(fromStart, toEnd, departmentId).all(),
    env.DB.prepare(attendanceSql).bind(fromStart, attendanceToEnd, departmentId).all(),
    env.DB.prepare(
      `SELECT id, name, position, nfc_uid, active
         FROM checkpoints
        WHERE department_id = ? AND active = 1
        ORDER BY position ASC, id ASC`,
    ).bind(departmentId).all(),
    env.DB.prepare(
      `SELECT id, nama, no_kad_pengenalan, no_pk, guard_status, jawatan, active
         FROM users
        WHERE department_id = ?
          AND active = 1
          AND LOWER(jawatan) IN ('patrol', 'supervisor')
        ORDER BY CASE WHEN no_pk IS NULL OR no_pk = '' THEN 1 ELSE 0 END,
                 CAST(no_pk AS INTEGER) ASC, nama ASC, id ASC`,
    ).bind(departmentId).all(),
  ]);

  const scans = scanResult.results ?? [];
  const attendance = attendanceResult.results ?? [];
  const checkpoints = (checkpointResult.results ?? []).map((row) => ({
    id: Number(row.id),
    name: row.name,
    position: Number(row.position || 0),
    nfcUid: row.nfc_uid || '',
    active: Number(row.active) === 1,
  }));
  const guards = (guardResult.results ?? []).map((row) => ({
    id: Number(row.id),
    nama: row.nama,
    no_kad_pengenalan: row.no_kad_pengenalan || '',
    no_pk: row.no_pk || '',
    guard_status: row.guard_status || 'Tetap',
    jawatan: row.jawatan || 'patrol',
    active: Number(row.active) === 1,
  }));

  return json({
    from,
    to,
    department: {
      id: Number(departmentMeta.id),
      name: departmentMeta.name,
      companyId: departmentMeta.company_id == null ? null : Number(departmentMeta.company_id),
      companyName: departmentMeta.company_name || '',
      zone: departmentMeta.zone || '',
      state: 'KEDAH',
    },
    scans,
    attendance,
    checkpoints,
    guards,
    summary: {
      totalScans: scans.length,
      attendancePunches: attendance.length,
      activeCheckpoints: checkpoints.length,
      activeGuards: guards.length,
    },
  });
}

async function requireReportAccess(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  const user = await env.DB.prepare(
    `SELECT u.id, u.jawatan, u.company_id
       FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
      LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  const role = String(user.jawatan || '').trim().toLowerCase();
  if (role !== 'management' && role !== 'administration') {
    return { response: json({ error: 'Akses laporan hanya untuk Admin Sistem atau Pentadbiran Syarikat.' }, 403) };
  }
  if (role === 'administration' && !Number(user.company_id || 0)) {
    return { response: json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Syarikat.' }, 409) };
  }
  return { user };
}

function malaysiaStartIso(dateKey) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return null;
  const value = new Date(`${dateKey}T00:00:00+08:00`);
  return Number.isNaN(value.getTime()) ? null : value.toISOString();
}

function malaysiaEndIso(dateKey) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return null;
  const value = new Date(`${dateKey}T00:00:00+08:00`);
  if (Number.isNaN(value.getTime())) return null;
  value.setUTCDate(value.getUTCDate() + 1);
  return value.toISOString();
}

function addUtcDays(iso, days) {
  if (!iso) return null;
  const value = new Date(iso);
  if (Number.isNaN(value.getTime())) return null;
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString();
}

async function denyAdministrationOperationalAccess(request, env) {
  const token = getSessionToken(request);
  if (!token) return null;
  const user = await env.DB.prepare(
    `SELECT u.jawatan
       FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
      LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (String(user?.jawatan || '').trim().toLowerCase() !== 'administration') {
    return null;
  }
  return json({
    error: 'Akaun Pentadbiran Syarikat hanya dibenarkan mengakses dan memuat turun laporan PDF.',
  }, 403);
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();
  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) {
      try { return decodeURIComponent(value.join('=')); } catch (_) { return value.join('='); }
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
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
