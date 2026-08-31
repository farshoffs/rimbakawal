from pathlib import Path

history_path = Path('lib/features/history/clocking_history_screen.dart')
history = history_path.read_text(encoding='utf-8')
old = """                      if (visibleRuns.isEmpty)\n                        const Card(\n"""
new = """                      if (visibleRuns.isEmpty)\n                        Card(\n"""
if old not in history:
    raise SystemExit('Expected filtered empty-state const Card was not found')
history = history.replace(old, new, 1)
history_path.write_text(history, encoding='utf-8')

attendance_path = Path('lib/features/admin/attendance_history_screen.dart')
attendance = attendance_path.read_text(encoding='utf-8')
old_wait = """          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());\n"""
new_wait = """          if (snapshot.connectionState == ConnectionState.waiting) {\n            return const Center(child: CircularProgressIndicator());\n          }\n"""
old_error = """          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(snapshot.error.toString())));\n"""
new_error = """          if (snapshot.hasError) {\n            return Center(\n              child: Padding(\n                padding: const EdgeInsets.all(24),\n                child: Text(snapshot.error.toString()),\n              ),\n            );\n          }\n"""
if old_wait not in attendance or old_error not in attendance:
    raise SystemExit('Expected AttendanceHistory FutureBuilder one-line if statements were not found')
attendance = attendance.replace(old_wait, new_wait, 1)
attendance = attendance.replace(old_error, new_error, 1)
attendance_path.write_text(attendance, encoding='utf-8')

print('Fixed period UI analyzer issues.')
