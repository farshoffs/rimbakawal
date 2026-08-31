import attendanceWorker from './attendance.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {
      return monthlyReport(request, env, ctx, url);
    }
    return attendanceWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    if (typeof attendanceWorker.scheduled === 'function') {
      return attendanceWorker.scheduled(event, env, ctx);
    }
  },
};

async function monthlyReport(request, env, ctx, url) {
  const downstream = await attendanceWorker.fetch(request, env, ctx);
  if (!downstream.ok) return downstream;

  const payload = await downstream.json();
  const from = String(payload.from || '');
  const to = String(payload.to || '');
  const fromStart = malaysiaStartIso(from);
  const toEnd = malaysiaEndIso(to);
  if (!fromStart || !toEnd) return json({ error: 'Tarikh laporan tidak sah.' }, 400);

  const rawDepartmentId = url.searchParams.get('departmentId');
  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);
  const bindings = departmentId == null
    ? [fromStart, toEnd]
    : [fromStart, toEnd, departmentId];

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

  const attendanceSql = `SELECT a.id, a.user_id, a.department_id, a.work_date,
              a.punch_type, a.punched_at,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan
       FROM attendance_records a
       JOIN users u ON u.id = a.user_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE a.punched_at >= ? AND a.punched_at < ?
       ${departmentId == null ? '' : 'AND a.department_id = ?'}
       ORDER BY a.punched_at ASC, a.id ASC`;

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

  const [scanResult, attendanceResult, checkpointResult] = await Promise.all([
    env.DB.prepare(scanSql).bind(...bindings).all(),
    env.DB.prepare(attendanceSql).bind(...bindings).all(),
    checkpointPromise,
  ]);

  if (departmentMeta) {
    payload.department = {
      id: Number(departmentMeta.id),
      name: departmentMeta.name,
      companyName: departmentMeta.company_name || '',
      zone: departmentMeta.zone || '',
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
  payload.summary = {
    ...(payload.summary ?? {}),
    totalScans: payload.scans.length,
    attendancePunches: payload.attendance.length,
    activeCheckpoints: payload.checkpoints.length,
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

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}
