from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Expected text not found in {path}: {old[:120]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


def remove_range(path: str, start_marker: str, end_marker: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'Start marker not found in {path}: {start_marker!r}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'End marker not found in {path}: {end_marker!r}')
    file.write_text(text[:start] + text[end:], encoding='utf-8')


# 1) Native builds must always use the real NFC service. Web can keep its mock.
replace_once(
    'lib/main.dart',
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';",
)
replace_once(
    'lib/main.dart',
    '    _nfcService = useMockNfc ? MockNfcService() : RealNfcService();',
    "    _nfcService = kIsWeb\n        ? (useMockNfc ? MockNfcService() : RealNfcService())\n        : RealNfcService();",
)

# Make NFC availability/platform handling safe and explicit for Android/iOS.
replace_once(
    'lib/core/nfc/real_nfc_service.dart',
    "import 'dart:io';\n",
    "import 'package:flutter/foundation.dart';\n",
)
replace_once(
    'lib/core/nfc/real_nfc_service.dart',
    "  Future<bool> isAvailable() async {\n    final availability = await _manager.checkAvailability();\n    return availability == NfcAvailability.enabled;\n  }",
    "  Future<bool> isAvailable() async {\n    if (kIsWeb) return false;\n    if (defaultTargetPlatform != TargetPlatform.android &&\n        defaultTargetPlatform != TargetPlatform.iOS) {\n      return false;\n    }\n    try {\n      final availability = await _manager.checkAvailability();\n      return availability == NfcAvailability.enabled;\n    } catch (_) {\n      return false;\n    }\n  }",
)
replace_once(
    'lib/core/nfc/real_nfc_service.dart',
    '    if (Platform.isAndroid) {',
    '    if (defaultTargetPlatform == TargetPlatform.android) {',
)
real_nfc = Path('lib/core/nfc/real_nfc_service.dart')
text = real_nfc.read_text(encoding='utf-8')
if text.count('Platform.isIOS') != 2:
    raise SystemExit('Expected exactly two Platform.isIOS checks in real_nfc_service.dart')
real_nfc.write_text(
    text.replace('Platform.isIOS', 'defaultTargetPlatform == TargetPlatform.iOS'),
    encoding='utf-8',
)

replace_once(
    'lib/core/nfc/nfc_scan_prompt.dart',
    "          'NFC tidak tersedia. Pastikan telefon menyokong NFC dan hidupkan NFC dalam Tetapan Android.',",
    "          'NFC tidak tersedia. Pastikan peranti menyokong NFC. Pada Android, hidupkan NFC dalam Tetapan. Pada iPhone, gunakan peranti yang menyokong Core NFC.',",
)

# 2) Remove dashboard testing alarm / SOS controls entirely.
dashboard = Path('lib/features/dashboard/dashboard_screen.dart')
text = dashboard.read_text(encoding='utf-8')
for line in [
    "import 'package:audioplayers/audioplayers.dart';\n",
    "import 'package:flutter/services.dart';\n",
    "import 'package:geolocator/geolocator.dart';\n",
    '  final AudioPlayer _alarmPlayer = AudioPlayer();\n',
    '  bool _alarmShowing = false;\n',
    '    _alarmPlayer.dispose();\n',
    '      await _alarmPlayer.stop();\n',
]:
    if line not in text:
        raise SystemExit(f'Expected dashboard line not found: {line!r}')
    text = text.replace(line, '', 1)
dashboard.write_text(text, encoding='utf-8')

remove_range(
    'lib/features/dashboard/dashboard_screen.dart',
    '  Future<void> _playAlarm() async {',
    '  Future<void> _enableNotifications() async {',
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "          IconButton(\n            tooltip: 'Penggera / SOS',\n            onPressed: _showQuickActions,\n            icon: const Icon(Icons.crisis_alert_rounded),\n          ),\n",
    '',
)

# 3) Add the real SOS action to Rondaan Aktif, including current patrol location/session.
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\n",
)

patrol_sos_method = r'''  Future<void> _triggerSos() async {
    if (_ending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aktifkan SOS?'),
        content: const Text(
          'SOS akan direkod bersama lokasi rondaan semasa dan dihantar kepada pemantauan RimbaKawal. Ia tidak menghubungi talian kecemasan secara automatik.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.sos_rounded),
            label: const Text('AKTIFKAN SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _store.queueEvent(
        userId: widget.user.id,
        type: 'sos',
        location: await _captureEventLocation(),
        payload: {
          'note': 'SOS dicetuskan semasa Rondaan Aktif',
          'clientSessionId': _clientSessionId,
        },
      );
      unawaited(_sync.syncNow());
      await SystemSound.play(SystemSoundType.alert);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SOS telah direkod dan sedang dihantar kepada pusat pemantauan.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    }
  }

'''
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    '  Future<void> _toggleTorch() async {',
    patrol_sos_method + '  Future<void> _toggleTorch() async {',
)

sos_button = r'''              const SizedBox(height: 12),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: _ending ? null : _triggerSos,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC0392B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.sos_rounded, size: 28),
                  label: const Text(
                    'SOS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
'''
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    '              if (_error != null) ...[',
    sos_button + '              if (_error != null) ...[',
)

# 4) Make notification popup text explicitly white on its dark/grey surface.
replace_once(
    'lib/core/notifications/notification_alert_gate.dart',
    "        builder: (context) => AlertDialog(\n          icon: Icon(_icon(alert.kind), size: 48, color: _accent(alert.kind)),\n          title: Text(alert.title, textAlign: TextAlign.center),\n          content: Text(alert.body, textAlign: TextAlign.center),",
    "        builder: (context) => AlertDialog(\n          backgroundColor: const Color(0xFF222636),\n          icon: Icon(_icon(alert.kind), size: 48, color: _accent(alert.kind)),\n          title: Text(\n            alert.title,\n            textAlign: TextAlign.center,\n            style: const TextStyle(\n              color: Colors.white,\n              fontWeight: FontWeight.w900,\n            ),\n          ),\n          content: Text(\n            alert.body,\n            textAlign: TextAlign.center,\n            style: const TextStyle(color: Colors.white),\n          ),",
)

# 5) Produce an actual .ipa artifact (unsigned) alongside the APK/AAB.
workflow = Path('.github/workflows/build-mobile-production.yml')
text = workflow.read_text(encoding='utf-8')
old_package = '''      - name: Package unsigned iOS app
        working-directory: ${{ runner.temp }}/rimbakawal-mobile/build/ios/iphoneos
        run: zip -qry "$RUNNER_TEMP/RimbaKawal-iOS-Production-Unsigned.zip" Runner.app

      - name: Upload iOS release file
        uses: actions/upload-artifact@v4
        with:
          name: RimbaKawal-iOS-Production-Unsigned
          if-no-files-found: error
          retention-days: 14
          path: ${{ runner.temp }}/RimbaKawal-iOS-Production-Unsigned.zip
'''
new_package = '''      - name: Package unsigned iOS IPA
        shell: bash
        run: |
          set -euo pipefail
          rm -rf "$RUNNER_TEMP/Payload"
          mkdir -p "$RUNNER_TEMP/Payload"
          cp -R "$RUNNER_TEMP/rimbakawal-mobile/build/ios/iphoneos/Runner.app" "$RUNNER_TEMP/Payload/Runner.app"
          cd "$RUNNER_TEMP"
          zip -qry RimbaKawal-iOS-Production-Unsigned.ipa Payload

      - name: Upload iOS release file
        uses: actions/upload-artifact@v4
        with:
          name: RimbaKawal-iOS-Production-Unsigned
          if-no-files-found: error
          retention-days: 14
          path: ${{ runner.temp }}/RimbaKawal-iOS-Production-Unsigned.ipa
'''
if old_package in text:
    workflow.write_text(text.replace(old_package, new_package, 1), encoding='utf-8')
elif new_package not in text:
    raise SystemExit('Expected old or new iOS packaging block not found in build-mobile-production.yml')

# Bump build version so the rebuilt mobile artifacts are distinguishable.
replace_once('pubspec.yaml', 'version: 0.5.1+17', 'version: 0.5.2+18')

print('Native NFC, patrol SOS, notification contrast, and mobile artifact patch applied.')
