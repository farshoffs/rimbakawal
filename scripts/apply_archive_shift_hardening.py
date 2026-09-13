from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# An unmatched IN should survive midnight, but must not stay open forever if a
# guard forgot to punch OUT. Twenty-four hours safely covers the 20:00->08:00
# workflow and reasonable overtime while preventing an old IN becoming OUT.
replace_once(
    'worker/attendance.js',
    "const DEFAULT_RADIUS_M = 150;\n",
    "const DEFAULT_RADIUS_M = 150;\nconst MAX_OPEN_SHIFT_MS = 24 * 60 * 60 * 1000;\n",
)
replace_once(
    'worker/attendance.js',
    "const hasOpenShift = latestGlobal?.punch_type === 'IN';\n",
    "const hasOpenShift = latestGlobal?.punch_type === 'IN'\n    && Date.now() - Date.parse(latestGlobal.punched_at) <= MAX_OPEN_SHIFT_MS;\n",
)
replace_once(
    'worker/attendance.js',
    """  const punchType = latest?.punch_type === 'IN' ? 'OUT' : 'IN';
  // OUT belongs to the same work/shift date as its preceding IN even when the
  // calendar has crossed midnight (for example 20:00 -> 08:00).
  const workDate = punchType === 'OUT' && latest?.work_date
    ? String(latest.work_date)
    : todayWorkDate;
""",
    """  const hasOpenShift = latest?.punch_type === 'IN'
    && Date.now() - Date.parse(latest.punched_at) <= MAX_OPEN_SHIFT_MS;
  const punchType = hasOpenShift ? 'OUT' : 'IN';
  // OUT belongs to the same work/shift date as its preceding IN even when the
  // calendar has crossed midnight (for example 20:00 -> 08:00).
  const workDate = punchType === 'OUT' && latest?.work_date
    ? String(latest.work_date)
    : todayWorkDate;
""",
)

# Archive company users whether they are linked directly by company_id or
# indirectly through a school. This also covers older/legacy guard records.
replace_once(
    'worker/company_management.js',
    "env.DB.prepare('SELECT id, active FROM users WHERE company_id = ? ORDER BY id').bind(companyId).all(),\n",
    """env.DB.prepare(`SELECT u.id, u.active
                      FROM users u
                      LEFT JOIN departments d ON d.id = u.department_id
                     WHERE u.company_id = ? OR d.company_id = ?
                     ORDER BY u.id`).bind(companyId, companyId).all(),
""",
)
replace_once(
    'worker/company_management.js',
    "env.DB.prepare('UPDATE users SET active = 0 WHERE company_id = ?').bind(companyId),\n",
    """env.DB.prepare(`UPDATE users
                         SET active = 0
                       WHERE company_id = ?
                          OR department_id IN (SELECT id FROM departments WHERE company_id = ?)`)
      .bind(companyId, companyId),
""",
)

print('Applied stale-shift and legacy company archive hardening.')
