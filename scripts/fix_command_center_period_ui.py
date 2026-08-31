from pathlib import Path

history_path = Path('lib/features/history/clocking_history_screen.dart')
history = history_path.read_text(encoding='utf-8')
old = """                      if (visibleRuns.isEmpty)\n                        const Card(\n"""
new = """                      if (visibleRuns.isEmpty)\n                        Card(\n"""
if old not in history:
    raise SystemExit('Expected filtered empty-state const Card was not found')
history = history.replace(old, new, 1)
history_path.write_text(history, encoding='utf-8')

print('Fixed dynamic Sejarah Rondaan empty state.')
