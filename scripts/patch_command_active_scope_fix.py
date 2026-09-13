from pathlib import Path

path = Path('worker/command_center_period.js')
text = path.read_text(encoding='utf-8')
old = """           ${scopeDepartment ? 'WHERE u.department_id = ?' : ''}`,
        ).bind(...(scopeValue ? [liveSince, scopeValue] : [liveSince])).all()"""
new = """           ${scopeDepartment
             ? 'WHERE u.department_id = ?'
             : scopeCompany
               ? 'WHERE u.department_id IN (SELECT id FROM departments WHERE company_id = ?)'
               : ''}`,
        ).bind(...(scopeValue ? [liveSince, scopeValue] : [liveSince])).all()"""
if text.count(old) != 1:
    raise SystemExit(f'active patrol scope block: {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
