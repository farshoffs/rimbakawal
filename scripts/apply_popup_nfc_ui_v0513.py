from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str, label: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f'{label}: expected marker not found in {path}')
    write(path, text.replace(old, new, 1))


# Version bump.
replace_once(
    'pubspec.yaml',
    'version: 0.5.12+28',
    'version: 0.5.13+29',
    'version bump',
)

# Notification popup gate now knows the signed-in role so patrol-complete popup
# can be suppressed for guards only, while the push notification itself remains.
notification_path = 'lib/core/notifications/notification_alert_gate.dart'
replace_once(
    notification_path,
    "import 'package:flutter/material.dart';\n\nimport 'notification_service.dart';",
    "import 'package:flutter/material.dart';\n\nimport '../api/app_user.dart';\nimport 'notification_service.dart';",
    'notification AppUser import',
)
replace_once(
    notification_path,
    "class NotificationAlertGate extends StatefulWidget {\n  const NotificationAlertGate({required this.child, super.key});\n  final Widget child;",
    "class NotificationAlertGate extends StatefulWidget {\n  const NotificationAlertGate({\n    required this.user,\n    required this.child,\n    super.key,\n  });\n\n  final AppUser user;\n  final Widget child;",
    'notification gate user parameter',
)
replace_once(
    notification_path,
    "    // SOS has a dedicated full-screen alarm/polling experience.\n    if (alert.kind == 'sos') return;\n    _showing = true;",
    "    // SOS has a dedicated full-screen alarm/polling experience.\n    if (alert.kind == 'sos') return;\n\n    // These actions already provide immediate on-screen feedback in their\n    // own workflow. Keep FCM/system notifications, but do not interrupt the\n    // user with an extra foreground popup.\n    if (alert.kind == 'checkpoint_scanned' ||\n        alert.kind == 'attendance_punch') {\n      return;\n    }\n    if (alert.kind == 'patrol_completed' &&\n        widget.user.jawatan.toLowerCase() == 'patrol') {\n      return;\n    }\n\n    _showing = true;",
    'foreground popup suppression',
)
replace_once(
    notification_path,
    "            TextButton(\n              onPressed: () => Navigator.of(context).pop(),\n              child: const Text('TUTUP'),\n            ),",
    "            OutlinedButton.icon(\n              onPressed: () => Navigator.of(context).pop(),\n              icon: const Icon(Icons.close_rounded),\n              label: const Text('TUTUP'),\n            ),",
    'notification close button',
)

# Pass the current user into NotificationAlertGate from both auth entry paths.
replace_once(
    'lib/main.dart',
    "        return NotificationAlertGate(\n          child: SosAlertGate(",
    "        return NotificationAlertGate(\n          user: user,\n          child: SosAlertGate(",
    'restored session notification gate user',
)
replace_once(
    'lib/features/auth/login_screen.dart',
    "          builder: (_) => NotificationAlertGate(\n            child: SosAlertGate(",
    "          builder: (_) => NotificationAlertGate(\n            user: user,\n            child: SosAlertGate(",
    'manual login notification gate user',
)

# Remove local success snackbar after checkpoint scan. Errors and NFC scan UI
# remain unchanged. Background/system push still remains available.
patrol_path = 'lib/features/patrol/patrol_screen.dart'
replace_once(
    patrol_path,
    "      if (!mounted) return;\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            _store.isNfcTestMode\n                ? 'DUMMY • ${checkpoint.name} telah direkod dan akan disegerakkan secara automatik.'\n                : '${checkpoint.name} telah disimpan pada peranti dan akan disegerakkan secara automatik.',\n          ),\n        ),\n      );\n      setState(() {});",
    "      if (!mounted) return;\n      setState(() {});",
    'checkpoint scan success snackbar',
)

# Remove local success snackbar after punch in/out. Status refresh remains, and
# server push notification remains unchanged.
attendance_path = 'lib/features/attendance/attendance_screen.dart'
replace_once(
    attendance_path,
    "      if (!mounted) return;\n      final label = record.punchType == 'IN' ? 'MASUK' : 'KELUAR';\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            'Punch $label berjaya • ${record.distanceMeters.toStringAsFixed(0)}m dari pusat kawasan.',\n          ),\n        ),\n      );",
    "      if (!mounted) return;",
    'attendance success snackbar',
)

# The punch response is no longer referenced after removing the snackbar.
replace_once(
    attendance_path,
    "      final record = await widget.api.punchAttendance(\n        latitude: position.latitude,\n        longitude: position.longitude,\n        accuracy: position.accuracy,\n        selfieData: dataUrl,\n      );",
    "      await widget.api.punchAttendance(\n        latitude: position.latitude,\n        longitude: position.longitude,\n        accuracy: position.accuracy,\n        selfieData: dataUrl,\n      );",
    'unused attendance record result',
)

# Checkpoint admin UI: remove NDEF rewrite workflow entirely. Registration now
# reads the physical/logical ID exactly as before via the read-only scan path.
department_path = 'lib/features/admin/department_maintenance_screen.dart'
department = read(department_path)
method_pattern = re.compile(
    r"\n  Future<void> _rewriteTag\(\) async \{[\s\S]*?\n  \}\n\n  Future<void> _readTagOnly\(\) async \{"
)
department, count = method_pattern.subn(
    "\n  Future<void> _readTagOnly() async {",
    department,
    count=1,
)
if count != 1:
    raise SystemExit('checkpoint rewrite method marker not found')

old_controls = """              TextField(
                controller: _uidController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'ID checkpoint RimbaKawal / UID',
                  hintText: 'Tulis semula tag untuk menjana ID checkpoint',
                  prefixIcon: Icon(Icons.nfc_rounded),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _rewriteTag,
                  icon: const Icon(Icons.edit_rounded),
                  label: Text(
                    _scanning ? 'PROSES NFC…' : 'TULIS SEMULA & DAFTAR TAG',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _scanning ? null : _readTagOnly,
                  icon: const Icon(Icons.nfc_rounded),
                  label: const Text('BACA ID / UID SAHAJA'),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'RimbaKawal akan overwrite kandungan NDEF tag dengan ID checkpoint sendiri dan membaca semula ID itu untuk pengesahan. UID cip fizikal NTAG213/215/216 ditetapkan kilang dan tidak boleh ditulis semula. Gunakan Baca ID / UID Sahaja untuk tag lama atau diagnosis tanpa mengubah tag.',
                  style: TextStyle(fontSize: 12),
                ),
              ),"""
new_controls = """              TextField(
                controller: _uidController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'ID / UID Tag NFC',
                  hintText: 'Tekan Daftar Tag dan imbas tag NFC',
                  prefixIcon: Icon(Icons.nfc_rounded),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _readTagOnly,
                  icon: const Icon(Icons.nfc_rounded),
                  label: Text(_scanning ? 'MENGIMBAS…' : 'DAFTAR TAG'),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Daftar Tag hanya membaca ID/UID tag NFC dan mengaitkannya dengan checkpoint ini. Kandungan tag tidak ditulis atau diubah.',
                  style: TextStyle(fontSize: 12),
                ),
              ),"""
if old_controls not in department:
    raise SystemExit('checkpoint NFC controls marker not found')
department = department.replace(old_controls, new_controls, 1)
department = department.replace(
    "          content: Text('ID / UID dibaca: ${scan.tagId}'),",
    "          content: Text('Tag berjaya didaftarkan: ${scan.tagId}'),",
    1,
)
write(department_path, department)

# Make secondary dialog actions visibly button-shaped throughout the app.
# Existing OutlinedButtons are left untouched; only TextButton variants whose
# own label is a close/cancel/back/no action are promoted.
secondary_labels = {
    'Batal', 'BATAL', 'Tutup', 'TUTUP', 'Kembali', 'KEMBALI',
    'Tidak', 'TIDAK', 'Nanti', 'NANTI',
}
for path in Path('lib').rglob('*.dart'):
    text = path.read_text(encoding='utf-8')
    for token, replacement in (
        ('TextButton.icon(', 'OutlinedButton.icon('),
        ('TextButton(', 'OutlinedButton('),
    ):
        cursor = 0
        while True:
            index = text.find(token, cursor)
            if index < 0:
                break
            window = text[index:index + 900]
            label_positions = []
            for label in secondary_labels:
                for marker in (
                    f"Text('{label}')",
                    f'Text("{label}")',
                ):
                    pos = window.find(marker)
                    if pos >= 0:
                        label_positions.append(pos)
            label_pos = min(label_positions) if label_positions else -1
            next_positions = [
                p for p in (
                    window.find('TextButton(', len(token)),
                    window.find('TextButton.icon(', len(token)),
                    window.find('FilledButton(', len(token)),
                    window.find('FilledButton.icon(', len(token)),
                    window.find('OutlinedButton(', len(token)),
                    window.find('OutlinedButton.icon(', len(token)),
                ) if p >= 0
            ]
            next_button = min(next_positions) if next_positions else -1
            if label_pos >= 0 and (next_button < 0 or label_pos < next_button):
                text = text[:index] + replacement + text[index + len(token):]
                cursor = index + len(replacement)
            else:
                cursor = index + len(token)
    path.write_text(text, encoding='utf-8')

# Guard rails.
notification = read(notification_path)
if "alert.kind == 'checkpoint_scanned'" not in notification:
    raise SystemExit('checkpoint popup suppression missing')
if "alert.kind == 'attendance_punch'" not in notification:
    raise SystemExit('attendance popup suppression missing')
if "widget.user.jawatan.toLowerCase() == 'patrol'" not in notification:
    raise SystemExit('guard-only patrol-complete popup suppression missing')

department = read(department_path)
for forbidden in ('TULIS SEMULA & DAFTAR TAG', 'BACA ID / UID SAHAJA', '_rewriteTag'):
    if forbidden in department:
        raise SystemExit(f'forbidden checkpoint writer UI remains: {forbidden}')
if 'DAFTAR TAG' not in department:
    raise SystemExit('Daftar Tag control missing')

print('Popup/NFC UI v0.5.13+29 patch applied.')
