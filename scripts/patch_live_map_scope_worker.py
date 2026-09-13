from pathlib import Path
p=Path('worker/offline.js')
t=p.read_text(encoding='utf-8')
old="""      if (url.pathname === '/api/monitor/live-map' && request.method === 'GET') {
        return liveMap(request, env);
      }"""
new="""      if (url.pathname === '/api/monitor/live-map' && request.method === 'GET') {
        return liveMap(request, env, url);
      }"""
if t.count(old)!=1: raise SystemExit(f'route {t.count(old)}')
t=t.replace(old,new,1)
old="""async function liveMap(request, env) {
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
    ).all(),"""
new="""async function liveMap(request, env, url) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  const now = new Date();
  const trailSince = new Date(now.getTime() - 60 * 60 * 1000).toISOString();
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const requestedDepartment = Number(url.searchParams.get('departmentId') || 0) || null;
  const requestedCompany = Number(url.searchParams.get('companyId') || 0) || null;
  const scopeDepartment = role === 'management'
    ? requestedDepartment
    : Number(auth.user.department_id || 0) || null;
  const scopeCompany = role === 'management' && !scopeDepartment ? requestedCompany : null;
  const where = ['p.active = 1', 'u.active = 1'];
  const binds = [];
  if (scopeDepartment) {
    where.push('p.department_id = ?');
    binds.push(scopeDepartment);
  } else if (scopeCompany) {
    where.push('d.company_id = ?');
    binds.push(scopeCompany);
  }

  const [presenceResult, trailResult] = await Promise.all([
    env.DB.prepare(
      `SELECT p.user_id, p.department_id, p.client_session_id, p.started_at,
              p.last_latitude, p.last_longitude, p.last_accuracy, p.last_location_at,
              u.nama, u.profile_picture, COALESCE(d.name, u.jabatan) AS jabatan,
              d.company_id, COALESCE(co.name, d.company_name, '') AS company_name
       FROM live_patrol_presence p
       JOIN users u ON u.id = p.user_id
       LEFT JOIN departments d ON d.id = p.department_id
       LEFT JOIN companies co ON co.id = d.company_id
       WHERE ${where.join(' AND ')}
       ORDER BY p.updated_at DESC`,
    ).bind(...binds).all(),"""
if t.count(old)!=1: raise SystemExit(f'function head {t.count(old)}')
t=t.replace(old,new,1)
old2="""      jabatan: row.jabatan,
      profilePicture: row.profile_picture,"""
new2="""      jabatan: row.jabatan,
      departmentId: row.department_id == null ? null : Number(row.department_id),
      companyId: row.company_id == null ? null : Number(row.company_id),
      companyName: row.company_name || '',
      profilePicture: row.profile_picture,"""
if t.count(old2)!=1: raise SystemExit(f'response {t.count(old2)}')
p.write_text(t.replace(old2,new2,1),encoding='utf-8')
