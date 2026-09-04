from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str, label: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/features/sos/sos_alert_gate.dart',
    """                            if (widget.user.canMonitor) ...[\n                              FilledButton.icon(\n                                style: FilledButton.styleFrom(\n                                  backgroundColor: const Color(0xFF00B894),\n                                ),\n                                onPressed: () => unawaited(\n                                  _resolveFromAlert(dialogContext, id),\n                                ),\n                                icon: const Icon(Icons.task_alt_rounded),\n                                label: const Text('TANDAKAN SELESAI'),\n                              ),\n                              const SizedBox(height: 8),\n                            ],\n                            OutlinedButton.icon(\n                              onPressed: () =>\n                                  Navigator.of(dialogContext).pop(false),\n                              icon: const Icon(Icons.visibility_rounded),\n                              label: const Text('TUTUP AMARAN'),\n                            ),\n""",
    """                            if (widget.user.canMonitor) ...[\n                              SizedBox(\n                                width: double.infinity,\n                                child: FilledButton.icon(\n                                  style: FilledButton.styleFrom(\n                                    backgroundColor: const Color(0xFF00B894),\n                                  ),\n                                  onPressed: () => unawaited(\n                                    _resolveFromAlert(dialogContext, id),\n                                  ),\n                                  icon: const Icon(Icons.task_alt_rounded),\n                                  label: const Text('TANDAKAN SELESAI'),\n                                ),\n                              ),\n                              const SizedBox(height: 8),\n                            ],\n                            SizedBox(\n                              width: double.infinity,\n                              child: OutlinedButton.icon(\n                                onPressed: () =>\n                                    Navigator.of(dialogContext).pop(false),\n                                icon: const Icon(Icons.visibility_off_rounded),\n                                label: const Text('TUTUP AMARAN'),\n                              ),\n                            ),\n""",
    'SOS full-screen peer actions',
)

print('Applied button consistency patch v0.5.16')
