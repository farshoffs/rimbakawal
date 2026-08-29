from pathlib import Path

root = Path(__file__).resolve().parents[1]
patrol_path = root / 'lib/features/patrol/patrol_screen.dart'
pubspec_path = root / 'pubspec.yaml'


def replace_required(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new)
    if new in text:
        return text
    raise SystemExit(f'Padanan tidak ditemui untuk {label}')


source_files = list((root / 'lib').rglob('*.dart')) + list((root / 'worker').rglob('*.js'))
phrase_replacements = [
    ('TITIK PEMERIKSAAN', 'CHECKPOINT'),
    ('Titik Pemeriksaan', 'Checkpoint'),
    ('Titik pemeriksaan', 'Checkpoint'),
    ('titik pemeriksaan', 'checkpoint'),
    ('SIMULASI IMBASAN', 'IMBAS CHECKPOINT'),
    ('Simulasi Imbasan', 'Imbas Checkpoint'),
]

for path in source_files:
    text = path.read_text(encoding='utf-8')
    original = text
    for old, new in phrase_replacements:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text, encoding='utf-8')
        print(f'Istilah dikemas kini: {path.relative_to(root)}')


text = patrol_path.read_text(encoding='utf-8')
text = replace_required(
    text,
    "import 'package:image_picker/image_picker.dart';\n",
    "import 'package:image_picker/image_picker.dart';\nimport 'package:wakelock_plus/wakelock_plus.dart';\n",
    'import wakelock_plus',
)
text = replace_required(
    text,
    'class _PatrolScreenState extends State<PatrolScreen>\n    with SingleTickerProviderStateMixin {',
    'class _PatrolScreenState extends State<PatrolScreen> {',
    'buang SingleTickerProviderStateMixin',
)
text = text.replace('  late final AnimationController _pulseController;\n', '')
text = replace_required(
    text,
    "    _pulseController = AnimationController(\n      vsync: this,\n      duration: const Duration(milliseconds: 2100),\n    )..repeat();\n",
    '    unawaited(WakelockPlus.enable());\n',
    'aktifkan skrin kekal menyala',
)
text = replace_required(
    text,
    '    _pulseController.dispose();\n',
    '    unawaited(WakelockPlus.disable());\n',
    'matikan wakelock ketika keluar skrin',
)
text = text.replace('                animation: _pulseController,\n', '')
text = text.replace('    required this.animation,\n', '')
text = text.replace('  final Animation<double> animation;\n', '')

animated_avatar = """              AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Container(
                  padding: EdgeInsets.all(5 + animation.value * 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF6C5CE7)
                          .withValues(alpha: 1 - animation.value * 0.65),
                      width: 2,
                    ),
                  ),
                  child: child,
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: image,
                  child: image == null
                      ? Text(
                          user.nama.isEmpty ? '?' : user.nama[0],
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
"""
static_avatar = """              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: image,
                  child: image == null
                      ? Text(
                          user.nama.isEmpty ? '?' : user.nama[0],
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
"""
text = replace_required(text, animated_avatar, static_avatar, 'avatar statik Rondaan Aktif')
text = text.replace("? 'SIMULASI IMBASAN'", "? 'IMBAS CHECKPOINT'")
text = text.replace("? 'Simulasi Imbasan'", "? 'Imbas Checkpoint'")
patrol_path.write_text(text, encoding='utf-8')
print('Rondaan Aktif: animasi dibuang dan skrin kekal menyala diaktifkan')


pubspec = pubspec_path.read_text(encoding='utf-8')
if '  wakelock_plus:' not in pubspec:
    marker = '  url_launcher: ^6.3.2\n'
    if marker not in pubspec:
        raise SystemExit('Lokasi dependency url_launcher tidak ditemui dalam pubspec.yaml')
    pubspec = pubspec.replace(marker, marker + '  wakelock_plus: ^1.7.0\n')
    pubspec_path.write_text(pubspec, encoding='utf-8')
    print('Dependency wakelock_plus ditambah')
else:
    print('Dependency wakelock_plus sudah tersedia')


remaining_terms = []
for path in source_files:
    content = path.read_text(encoding='utf-8')
    for term in (
        'TITIK PEMERIKSAAN',
        'Titik Pemeriksaan',
        'Titik pemeriksaan',
        'titik pemeriksaan',
        'SIMULASI IMBASAN',
        'Simulasi Imbasan',
    ):
        if term in content:
            remaining_terms.append(f'{path.relative_to(root)} -> {term}')
if remaining_terms:
    raise SystemExit('Istilah lama masih ditemui:\n' + '\n'.join(remaining_terms))

patrol = patrol_path.read_text(encoding='utf-8')
for forbidden in ('_pulseController', 'SingleTickerProviderStateMixin', 'AnimatedBuilder('):
    if forbidden in patrol:
        raise SystemExit(f'Animasi lama masih ditemui pada patrol_screen.dart: {forbidden}')
for required in (
    "import 'package:wakelock_plus/wakelock_plus.dart';",
    'WakelockPlus.enable()',
    'WakelockPlus.disable()',
    "'IMBAS CHECKPOINT'",
):
    if required not in patrol:
        raise SystemExit(f'Perubahan wajib tidak ditemui pada patrol_screen.dart: {required}')

print('Audit checkpoint, animasi dan skrin kekal menyala: LULUS')
