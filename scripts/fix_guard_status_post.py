#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ui_path = ROOT / 'lib/features/admin/user_maintenance_screen.dart'
ui = ui_path.read_text(encoding='utf-8')

status_dropdown = """              DropdownButtonFormField<String>(
                initialValue: _guardStatus,
                decoration: const InputDecoration(
                  labelText: 'Status Pengawal',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                  helperText: 'Digunakan pada ruangan TETAP / GANTIAN Borang PKK 2.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Tetap',
                    child: Text('Tetap'),
                  ),
                  DropdownMenuItem(
                    value: 'Gantian',
                    child: Text('Gantian'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _guardStatus = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
"""

# The first migration script intentionally uses the same department marker twice.
# Collapse any accidental duplicate in Edit Pengguna.
while status_dropdown + status_dropdown in ui:
    ui = ui.replace(status_dropdown + status_dropdown, status_dropdown, 1)

# Ensure Add Pengguna has exactly one dropdown as well.
add_marker = 'class _AddUserDialogState extends State<_AddUserDialog> {'
add_pos = ui.index(add_marker)
head, add = ui[:add_pos], ui[add_pos:]
if add.count("initialValue: _guardStatus") == 0:
    department_marker = """              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _departmentId,
"""
    if department_marker not in add:
        raise SystemExit('Marker department dalam Add Pengguna tidak ditemui.')
    add = add.replace(
        department_marker,
        "              const SizedBox(height: 12),\n" + status_dropdown +
        "              DropdownButtonFormField<int>(\n                initialValue: _departmentId,\n",
        1,
    )
ui = head + add

if ui.count("initialValue: _guardStatus") != 2:
    raise SystemExit(
        f'Jumlah dropdown Status Pengawal tidak tepat: {ui.count("initialValue: _guardStatus")}'
    )
ui_path.write_text(ui, encoding='utf-8')

# Overwrite migration with clean SQL (without quote artifacts).
migration = ROOT / 'migrations/0017_guard_status.sql'
migration.write_text(
    "-- Status pengawal untuk Borang PKK 2 dan pentadbiran pengguna.\n"
    "ALTER TABLE users ADD COLUMN guard_status TEXT NOT NULL DEFAULT 'Tetap';\n\n"
    "UPDATE users\n"
    "SET guard_status = 'Gantian'\n"
    "WHERE UPPER(TRIM(nama)) = 'BUFFER';\n",
    encoding='utf-8',
)

print('Post patch OK: 2 dropdowns and BUFFER migration normalized.')
