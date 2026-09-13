from pathlib import Path
p=Path('worker/command_center_period.js')
t=p.read_text(encoding='utf-8')
old="""  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const scopeDepartment = role === 'management'
    ? null
    : Number(auth.user.department_id || 0) || null;
  const includesToday = from <= todayKey && to >= todayKey;"""
new="""  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const requestedDepartment = Number(url.searchParams.get('departmentId') || 0) || null;
  const requestedCompany = Number(url.searchParams.get('companyId') || 0) || null;
  const scopeDepartment = role === 'management'
    ? requestedDepartment
    : Number(auth.user.department_id || 0) || null;
  const scopeCompany = role === 'management' && !scopeDepartment ? requestedCompany : null;
  const scopeValue = scopeDepartment || scopeCompany || null;
  const scopeSql = (column) => scopeDepartment
    ? `AND ${column} = ?`
    : scopeCompany
      ? `AND ${column} IN (SELECT id FROM departments WHERE company_id = ?)`
      : '';
  const includesToday = from <= todayKey && to >= todayKey;"""
if t.count(old)!=1: raise SystemExit(f'scope setup {t.count(old)}')
t=t.replace(old,new,1)
for old,new in [
("${scopeDepartment ? 'AND u.department_id = ?' : ''}","${scopeSql('u.department_id')}"),
("${scopeDepartment ? 'AND c.department_id = ?' : ''}","${scopeSql('c.department_id')}"),
("${scopeDepartment ? 'AND a.department_id = ?' : ''}","${scopeSql('a.department_id')}"),
("${scopeDepartment ? 'AND i.department_id = ?' : ''}","${scopeSql('i.department_id')}"),
("${scopeDepartment ? 'AND e.department_id = ?' : ''}","${scopeSql('e.department_id')}"),
]:
    if old not in t: raise SystemExit(f'missing condition {old}')
    t=t.replace(old,new)
p.write_text(t,encoding='utf-8')
