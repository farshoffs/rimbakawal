from pathlib import Path

root = Path(__file__).resolve().parents[1]
replacements = {
    root / 'lib/features/admin/live_patrol_map_screen.dart': {
        "_ => 'WAITING GPS',": "_ => 'MENUNGGU LOKASI',",
    },
    root / 'lib/features/admin/sos_management_screen.dart': {
        "'Auto-refresh setiap 8 saat. Resolve memerlukan catatan audit.'":
            "'Paparan dikemas kini secara automatik setiap 8 saat. Penyelesaian SOS memerlukan catatan audit.'",
    },
}

for path, values in replacements.items():
    text = path.read_text(encoding='utf-8')
    original = text
    for old, new in values.items():
        if old not in text:
            raise SystemExit(f'Frasa sasaran tidak ditemui dalam {path.relative_to(root)}: {old}')
        text = text.replace(old, new)
    path.write_text(text, encoding='utf-8')
    print(f'Dikemas kini: {path.relative_to(root)}')

# Audit istilah Inggeris yang tidak sepatutnya terpapar sebagai label operasi.
terms = [
    'NFC + GPS live', 'Live operations', 'WAITING GPS', 'Auto-refresh',
    'Resolve memerlukan', 'OFFLINE READY', 'AUTO SYNC', 'SYNCING',
    ' PENDING', ' FAILED', 'STARTING', 'ON PATROL', 'LOCAL FIRST',
    'Scan checkpoint', 'SCANNING', 'SCAN NFC', 'MISSED CHECKPOINT',
    'Belum scan', 'Command Center', 'Status Guard', 'Incident Queue',
    'Operations Command Center', 'NO CHECKPOINT', "'WAITING'",
]
remaining = []
for path in (root / 'lib').rglob('*.dart'):
    text = path.read_text(encoding='utf-8')
    for term in terms:
        if term in text:
            remaining.append(f'{path.relative_to(root)} -> {term}')
if remaining:
    raise SystemExit('Istilah paparan lama masih ditemui:\n' + '\n'.join(remaining))
print('Audit istilah paparan: bersih')
