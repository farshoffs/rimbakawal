from pathlib import Path
p=Path('worker/sos.js')
t=p.read_text(encoding='utf-8')
start=t.index('async function resolveSos')
head,tail=t[:start],t[start:]
old="""  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const body = await readJson(request);"""
new="""  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  if (role !== 'management' && !auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const body = await readJson(request);"""
if tail.count(old)!=1: raise SystemExit(f'guard {tail.count(old)}')
p.write_text(head+tail.replace(old,new,1),encoding='utf-8')
