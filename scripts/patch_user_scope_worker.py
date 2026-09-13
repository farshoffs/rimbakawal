from pathlib import Path
p=Path('worker/index.js')
t=p.read_text(encoding='utf-8')
old="""      if (url.pathname === '/api/admin/users' && request.method === 'GET') {
        return adminUsers(request, env);
      }"""
new="""      if (url.pathname === '/api/admin/users' && request.method === 'GET') {
        return adminUsers(request, env, url);
      }"""
if t.count(old)!=1: raise SystemExit(f'route {t.count(old)}')
t=t.replace(old,new,1)
old="""async function adminUsers(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const result = await env.DB.prepare(
    `${userSelect()}
     ORDER BY u.nama ASC`,
  ).all();
  return json({ users: (result.results ?? []).map(publicUser) });
}"""
new="""async function adminUsers(request, env, url) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const departmentId = Number(url.searchParams.get('departmentId') || 0) || null;
  const companyId = Number(url.searchParams.get('companyId') || 0) || null;
  const where = [];
  const binds = [];
  if (departmentId) {
    where.push('u.department_id = ?');
    binds.push(departmentId);
  } else if (companyId) {
    where.push('COALESCE(u.company_id, d.company_id) = ?');
    binds.push(companyId);
  }
  const result = await env.DB.prepare(
    `${userSelect()}
     ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
     ORDER BY u.nama ASC`,
  ).bind(...binds).all();
  return json({ users: (result.results ?? []).map(publicUser) });
}"""
if t.count(old)!=1: raise SystemExit(f'function {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
