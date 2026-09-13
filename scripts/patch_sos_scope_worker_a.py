from pathlib import Path
p=Path('worker/sos.js')
t=p.read_text(encoding='utf-8')
old="""      if (url.pathname === '/api/sos/manage' && request.method === 'GET') {
        return getManagedSos(request, env);
      }"""
new="""      if (url.pathname === '/api/sos/manage' && request.method === 'GET') {
        return getManagedSos(request, env, url);
      }"""
if t.count(old)!=1: raise SystemExit(f'route {t.count(old)}')
t=t.replace(old,new,1)
old="""async function getManagedSos(request, env) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const result = await env.DB.prepare(
    `SELECT s.id, s.user_id, s.triggered_at, s.note, s.status,
            s.resolved_at, s.resolution_note,
            u.nama, u.jawatan, u.profile_picture,
            COALESCE(d.name, u.jabatan) AS jabatan,
            ru.nama AS resolved_by_name
     FROM sos_events s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN users ru ON ru.id = s.resolved_by_user_id
     LEFT JOIN departments d ON d.id = s.department_id
     WHERE s.department_id = ?
     ORDER BY CASE WHEN s.status = 'active' THEN 0 ELSE 1 END,
              s.triggered_at DESC, s.id DESC
     LIMIT 50`,
  ).bind(auth.user.department_id).all();"""
new="""async function getManagedSos(request, env, url) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const requestedDepartment = Number(url.searchParams.get('departmentId') || 0) || null;
  const requestedCompany = Number(url.searchParams.get('companyId') || 0) || null;
  const scopeDepartment = role === 'management'
    ? requestedDepartment
    : Number(auth.user.department_id || 0) || null;
  const scopeCompany = role === 'management' && !scopeDepartment ? requestedCompany : null;
  if (role !== 'management' && !scopeDepartment) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }
  const where = [];
  const binds = [];
  if (scopeDepartment) {
    where.push('s.department_id = ?');
    binds.push(scopeDepartment);
  } else if (scopeCompany) {
    where.push('d.company_id = ?');
    binds.push(scopeCompany);
  }

  const result = await env.DB.prepare(
    `SELECT s.id, s.user_id, s.department_id, s.triggered_at, s.note, s.status,
            s.resolved_at, s.resolution_note,
            u.nama, u.jawatan, u.profile_picture,
            COALESCE(d.name, u.jabatan) AS jabatan,
            d.company_id, COALESCE(co.name, d.company_name, '') AS company_name,
            ru.nama AS resolved_by_name
     FROM sos_events s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN users ru ON ru.id = s.resolved_by_user_id
     LEFT JOIN departments d ON d.id = s.department_id
     LEFT JOIN companies co ON co.id = d.company_id
     ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY CASE WHEN s.status = 'active' THEN 0 ELSE 1 END,
              s.triggered_at DESC, s.id DESC
     LIMIT 100`,
  ).bind(...binds).all();"""
if t.count(old)!=1: raise SystemExit(f'getManagedSos {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
