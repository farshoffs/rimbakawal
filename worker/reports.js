import commandCenterWorker from './command_center_period.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {
      return monthlyReport(request, env, ctx, url);
    }
    return commandCenterWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    if (typeof commandCenterWorker.scheduled === 'function') {
      return commandCenterWorker.scheduled(event, env, ctx);
    }
  },
};

async function monthlyReport(request, env, ctx, url) {
  const downstream = await commandCenterWorker.fetch(request, env, ctx);
  if (!downstream.ok) return downstream;

  const payload = await downstream.json();
  const from = String(payload.from || '');
  const to = String(payload.to || '');
  const fromStart = malaysiaStartIso(from);
  const toEnd = malaysiaEndIso(to);
  const attendanceToEnd = addUtcDays(toEnd, 1);
  if (!fromStart || !toEnd || !attendanceToEnd) {
    return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  }

  const rawDepartmentId = url.searchParams.get('departmentId');
  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);
  const scanBindings = departmentId == null
    ? [fromStart, toEnd]
    : [fromStart, toEnd, departmentId];
  const attendanceBindings = departmentId == null
    ? [fromStart, attendanceToEnd]
    : [fromStart, attendanceToEnd, departmentId];

  const scanSql = `SELECT s.id, s.user_id, s.checkpoint_id, s.scanned_at, s.nfc_uid, s.session_index,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan,
              COALESCE(c.name, 'Checkpoint') AS checkpoint_name,
              c.position AS checkpoint_position
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN departments d ON d.id = u.department_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE s.scanned_at >= ? AND s.scanned_at < ?
       ${departmentId == null ? '' : 'AND u.department_id = ?'}
       ORDER BY s.scanned_at ASC, s.session_index ASC, c.position ASC, s.id ASC`;

  // Include one extra Malaysian calendar day so a night-shift IN on the
  // last day of the selected month can be paired with its OUT the next day.
  // The PDF generator still includes a session only when its IN belongs to
  // the selected report month.
  const attendanceSql = `SELECT a.id, a.user_id, a.department_id, a.work_date,
              a.punch_type, a.punched_at,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan
       FROM attendance_records a
       JOIN users u ON u.id = a.user_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE a.punched_at >= ? AND a.punched_at < ?
       ${departmentId == null ? '' : 'AND a.department_id = ?'}
       ORDER BY a.user_id ASC, a.punched_at ASC, a.id ASC`;

  const departmentMeta = departmentId == null ? null : await env.DB.prepare(
    'SELECT id, name, company_name, zone FROM departments WHERE id = ? LIMIT 1',
  ).bind(departmentId).first();

  const checkpointPromise = departmentId == null
    ? Promise.resolve({ results: [] })
    : env.DB.prepare(
      `SELECT id, name, position, nfc_uid
       FROM checkpoints
       WHERE department_id = ? AND active = 1
       ORDER BY position ASC, id ASC`,
    ).bind(departmentId).all();

  const guardPromise = departmentId == null
    ? Promise.resolve({ results: [] })
    : env.DB.prepare(
      `SELECT id, nama, no_kad_pengenalan, no_pk, jawatan
       FROM users
       WHERE department_id = ?
         AND active = 1
         AND LOWER(jawatan) IN ('patrol', 'supervisor')
       ORDER BY CASE WHEN no_pk IS NULL OR no_pk = '' THEN 1 ELSE 0 END,
                CAST(no_pk AS INTEGER) ASC,
                nama ASC,
                id ASC`,
    ).bind(departmentId).all();

  const [scanResult, attendanceResult, checkpointResult, guardResult] = await Promise.all([
    env.DB.prepare(scanSql).bind(...scanBindings).all(),
    env.DB.prepare(attendanceSql).bind(...attendanceBindings).all(),
    checkpointPromise,
    guardPromise,
  ]);

  if (departmentMeta) {
    payload.department = {
      id: Number(departmentMeta.id),
      name: departmentMeta.name,
      companyName: departmentMeta.company_name || '',
      zone: departmentMeta.zone || '',
      state: 'KEDAH',
    };
  }
  payload.scans = scanResult.results ?? [];
  payload.attendance = attendanceResult.results ?? [];
  payload.checkpoints = (checkpointResult.results ?? []).map((row) => ({
    id: Number(row.id),
    name: row.name,
    position: Number(row.position || 0),
    nfcUid: row.nfc_uid || '',
  }));
  payload.guards = (guardResult.results ?? []).map((row) => ({
    id: Number(row.id),
    nama: row.nama,
    no_kad_pengenalan: row.no_kad_pengenalan || '',
    no_pk: row.no_pk || '',
    jawatan: row.jawatan || 'patrol',
  }));
  payload.summary = {
    ...(payload.summary ?? {}),
    totalScans: payload.scans.length,
    attendancePunches: payload.attendance.length,
    activeCheckpoints: payload.checkpoints.length,
    activeGuards: payload.guards.length,
  };
  return json(payload);
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

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}
