from pathlib import Path
p=Path('worker/sos.js')
t=p.read_text(encoding='utf-8')
old="""  const current = await env.DB.prepare(
    `SELECT id, user_id, status, resolved_at, resolution_note
     FROM sos_events
     WHERE id = ? AND department_id = ?
     LIMIT 1`,
  ).bind(sosId, auth.user.department_id).first();"""
new="""  const current = role === 'management'
    ? await env.DB.prepare(
        `SELECT id, user_id, department_id, status, resolved_at, resolution_note
         FROM sos_events WHERE id = ? LIMIT 1`,
      ).bind(sosId).first()
    : await env.DB.prepare(
        `SELECT id, user_id, department_id, status, resolved_at, resolution_note
         FROM sos_events WHERE id = ? AND department_id = ? LIMIT 1`,
      ).bind(sosId, auth.user.department_id).first();"""
if t.count(old)!=1: raise SystemExit(f'lookup {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
