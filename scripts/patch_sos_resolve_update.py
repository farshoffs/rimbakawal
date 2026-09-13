from pathlib import Path
p=Path('worker/sos.js')
t=p.read_text(encoding='utf-8')
old="""  await env.DB.prepare(
    `UPDATE sos_events
     SET status = 'resolved', resolved_at = ?, resolved_by_user_id = ?, resolution_note = ?
     WHERE id = ? AND department_id = ? AND status = 'active'`,
  ).bind(
    resolvedAt,
    auth.user.id,
    resolutionNote,
    sosId,
    auth.user.department_id,
  ).run();"""
new="""  await env.DB.prepare(
    `UPDATE sos_events
     SET status = 'resolved', resolved_at = ?, resolved_by_user_id = ?, resolution_note = ?
     WHERE id = ? AND status = 'active'`,
  ).bind(resolvedAt, auth.user.id, resolutionNote, sosId).run();"""
if t.count(old)!=1: raise SystemExit(f'update {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
