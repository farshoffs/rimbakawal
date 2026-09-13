from pathlib import Path
p=Path('worker/attendance.js')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("""  const departmentId = Number(url.searchParams.get('departmentId') || 0);

  const where = ['a.work_date = ?'];""","""  const departmentId = Number(url.searchParams.get('departmentId') || 0);
  const companyId = Number(url.searchParams.get('companyId') || 0);

  const where = ['a.work_date = ?'];""",'company param')
one("""  if (departmentId > 0) {
    where.push('a.department_id = ?');
    binds.push(departmentId);
  }""","""  if (departmentId > 0) {
    where.push('a.department_id = ?');
    binds.push(departmentId);
  } else if (companyId > 0) {
    where.push('d.company_id = ?');
    binds.push(companyId);
  }""",'where')
one("  const summary = await attendanceSummary(env, date, departmentId || null);","""  const summary = await attendanceSummary(
    env,
    date,
    departmentId || null,
    departmentId > 0 ? null : companyId || null,
  );""",'summary call')
one("""async function attendanceSummary(env, date, departmentId = null) {
  const usersSql = departmentId
    ? `SELECT COUNT(*) AS total FROM users WHERE active = 1 AND department_id = ?`
    : `SELECT COUNT(*) AS total FROM users WHERE active = 1`;
  const users = await env.DB.prepare(usersSql).bind(...(departmentId ? [departmentId] : [])).first();

  const scope = departmentId ? 'AND department_id = ?' : '';
  const bindings = departmentId ? [date, departmentId] : [date];""","""async function attendanceSummary(env, date, departmentId = null, companyId = null) {
  const usersSql = departmentId
    ? `SELECT COUNT(*) AS total FROM users WHERE active = 1 AND department_id = ?`
    : companyId
      ? `SELECT COUNT(*) AS total FROM users WHERE active = 1 AND department_id IN (SELECT id FROM departments WHERE company_id = ?)`
      : `SELECT COUNT(*) AS total FROM users WHERE active = 1`;
  const users = await env.DB.prepare(usersSql)
    .bind(...(departmentId ? [departmentId] : companyId ? [companyId] : []))
    .first();

  const scope = departmentId
    ? 'AND department_id = ?'
    : companyId
      ? 'AND department_id IN (SELECT id FROM departments WHERE company_id = ?)'
      : '';
  const bindings = departmentId
    ? [date, departmentId]
    : companyId
      ? [date, companyId]
      : [date];""",'summary function')
p.write_text(t,encoding='utf-8')
