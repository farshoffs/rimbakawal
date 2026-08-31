from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'Expected block not found in {path}: {old[:80]!r}')
    p.write_text(text.replace(old, new, 1))


# Checkpoint setup must only READ an already prepared tag.
path = 'lib/features/admin/department_maintenance_screen.dart'
replace_once(
    path,
    """      final checkpointId = await widget.nfcService.writeCheckpointTag();
      if (!mounted) return;
      setState(() => _uidController.text = checkpointId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag NFC berjaya ditetapkan untuk checkpoint ini.'),
        ),
      );""",
    """      final scan = await widget.nfcService.scan();
      if (!mounted) return;
      setState(() => _uidController.text = scan.tagId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag NFC berjaya dibaca dan disimpan untuk checkpoint ini.'),
        ),
      );""",
)
replace_once(
    path,
    """                  labelText: 'ID tag NFC',
                  hintText: 'Tekan Scan Tag untuk menetapkan tag',""",
    """                  labelText: 'Data / ID tag NFC',
                  hintText: 'Tekan Scan Tag untuk membaca tag sedia ada',""",
)
replace_once(
    path,
    """                  label: Text(_scanning ? 'MENULIS TAG…' : 'SCAN TAG'),""",
    """                  label: Text(_scanning ? 'MEMBACA TAG…' : 'SCAN TAG'),""",
)
replace_once(
    path,
    """                  'Untuk checkpoint baharu, tag akan ditulis dengan ID RimbaKawal. Untuk checkpoint sedia ada, Scan Tag akan menulis semula tag yang disentuh.',""",
    """                  'Scan Tag hanya membaca tag yang telah disediakan. RimbaKawal tidak akan menulis atau mengubah kandungan NFC. NDEF Text/URI akan digunakan jika ada; jika tiada, UID fizikal tag digunakan.',""",
)
replace_once(
    path,
    """                    'Versi web menggunakan simulasi penulisan NFC untuk ujian konfigurasi.',""",
    """                    'Versi web menggunakan simulasi bacaan NFC untuk ujian konfigurasi.',""",
)

# Remove the write API entirely from the app-facing service contract.
replace_once(
    'lib/core/nfc/nfc_service.dart',
    """  Future<NfcScanResult> scan();
  Future<String> writeCheckpointTag();
  Future<void> cancelScan();""",
    """  Future<NfcScanResult> scan();
  Future<void> cancelScan();""",
)

# Mock NFC is read-only too.
mock = Path('lib/core/nfc/mock_nfc_service.dart')
mock.write_text("""import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class MockNfcService implements NfcService {
  final List<String> _mockTags = const [
    'TEXT:CHECKPOINT-A',
    'TEXT:CHECKPOINT-B',
    '04:C3:D4:E5:F6:07:18',
  ];

  int _index = 0;
  int _scanGeneration = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<NfcScanResult> scan() async {
    final generation = ++_scanGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (generation != _scanGeneration) {
      throw const NfcScanCancelledException();
    }

    final tagId = _mockTags[_index % _mockTags.length];
    _index++;

    return NfcScanResult(
      tagId: tagId,
      scannedAt: DateTime.now(),
      technology: 'NFC-A (mock read-only)',
      ndefPayload: tagId.startsWith('TEXT:') ? tagId.substring(5) : null,
    );
  }

  @override
  Future<void> cancelScan() async {
    _scanGeneration++;
  }
}
""")

# Real NFC: no write path. Prefer manually prepared NDEF Text/URI/custom checkpoint
# values, otherwise fall back to the physical UID.
real = Path('lib/core/nfc/real_nfc_service.dart')
text = real.read_text()
text = text.replace("import 'dart:math';\n", '')
start = text.index('  @override\n  Future<String> writeCheckpointTag() async {')
end = text.index('  void _beginOperation(', start)
text = text[:start] + text[end:]
start = text.index('  NdefMessage _checkpointMessage(')
end = text.index('  void _completeIosError', start)
text = text[:start] + text[end:]
text = text.replace(
    """    final checkpointId = _checkpointIdFromMessage(_cachedMessage(tag));""",
    """    final ndefId = _readOnlyIdFromMessage(_cachedMessage(tag));""",
)
text = text.replace(
    """        tagId: checkpointId ?? _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty ? 'Android NFC' : androidTag.techList.join(', '),
        ndefPayload: checkpointId == null ? null : 'rimbakawal://checkpoint/$checkpointId',""",
    """        tagId: ndefId ?? _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty ? 'Android NFC' : androidTag.techList.join(', '),
        ndefPayload: ndefId,""",
)
text = text.replace(
    """      if (checkpointId != null) {
        return NfcScanResult(
          tagId: checkpointId,
          scannedAt: DateTime.now(),
          technology: 'iOS NDEF',
          ndefPayload: 'rimbakawal://checkpoint/$checkpointId',
        );
      }""",
    """      if (ndefId != null) {
        return NfcScanResult(
          tagId: ndefId,
          scannedAt: DateTime.now(),
          technology: 'iOS NDEF',
          ndefPayload: ndefId,
        );
      }""",
)
old_parser_start = text.index('  String? _checkpointIdFromMessage(')
old_parser_end = text.index('  void _completeIosError', old_parser_start)
new_parser = r'''  String? _readOnlyIdFromMessage(NdefMessage? message) {
    if (message == null) return null;

    // Preserve compatibility with tags written by older RimbaKawal builds.
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.external) continue;
      final type = utf8.decode(record.type, allowMalformed: true).toLowerCase();
      if (type != _checkpointRecordType) continue;
      final value = utf8.decode(record.payload, allowMalformed: true).trim();
      if (value.isNotEmpty) return value.toUpperCase();
    }

    // NFC Tools and similar apps commonly write NFC Forum Text or URI records.
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.wellKnown) continue;
      final type = utf8.decode(record.type, allowMalformed: true);
      if (type == 'T') {
        final value = _textRecordValue(record.payload);
        if (value != null && value.isNotEmpty) return _bounded('TEXT:$value');
      }
      if (type == 'U') {
        final value = _uriRecordValue(record.payload);
        if (value != null && value.isNotEmpty) return _bounded('URI:$value');
      }
    }

    // For another pre-written NDEF record, derive a stable read-only identifier
    // from its bytes. No tag content is modified.
    for (final record in message.records) {
      if (record.payload.isEmpty && record.type.isEmpty) continue;
      return 'NDEF:${_stableNdefFingerprint(record)}';
    }
    return null;
  }

  String? _textRecordValue(Uint8List payload) {
    if (payload.isEmpty) return null;
    final status = payload[0];
    final utf16 = (status & 0x80) != 0;
    final languageLength = status & 0x3F;
    final textStart = 1 + languageLength;
    if (utf16 || textStart >= payload.length) return null;
    return utf8.decode(payload.sublist(textStart), allowMalformed: true).trim();
  }

  String? _uriRecordValue(Uint8List payload) {
    if (payload.isEmpty) return null;
    const prefixes = <String>[
      '',
      'http://www.',
      'https://www.',
      'http://',
      'https://',
      'tel:',
      'mailto:',
      'ftp://anonymous:anonymous@',
      'ftp://ftp.',
      'ftps://',
      'sftp://',
      'smb://',
      'nfs://',
      'ftp://',
      'dav://',
      'news:',
      'telnet://',
      'imap:',
      'rtsp://',
      'urn:',
      'pop:',
      'sip:',
      'sips:',
      'tftp:',
      'btspp://',
      'btl2cap://',
      'btgoep://',
      'tcpobex://',
      'irdaobex://',
      'file://',
      'urn:epc:id:',
      'urn:epc:tag:',
      'urn:epc:pat:',
      'urn:epc:raw:',
      'urn:epc:',
      'urn:nfc:',
    ];
    final code = payload[0];
    final prefix = code < prefixes.length ? prefixes[code] : '';
    final rest = utf8.decode(payload.sublist(1), allowMalformed: true).trim();
    return '$prefix$rest';
  }

  String _bounded(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 120) return trimmed;
    return 'NDEF:${_fingerprintBytes(Uint8List.fromList(utf8.encode(trimmed)))}';
  }

  String _stableNdefFingerprint(NdefRecord record) {
    final bytes = Uint8List.fromList([
      ...record.type,
      0,
      ...record.identifier,
      0,
      ...record.payload,
    ]);
    return _fingerprintBytes(bytes);
  }

  String _fingerprintBytes(Uint8List bytes) {
    var a = 0x811C9DC5;
    var b = 0x9E3779B9;
    for (final byte in bytes) {
      a = ((a ^ byte) * 0x01000193) & 0xFFFFFFFF;
      b = ((b + byte + ((b << 6) & 0xFFFFFFFF) + (b >> 2))) & 0xFFFFFFFF;
    }
    String hex32(int value) => value.toRadixString(16).padLeft(8, '0').toUpperCase();
    return '${hex32(a)}${hex32(b)}';
  }

'''
text = text[:old_parser_start] + new_parser + text[old_parser_end:]
real.write_text(text)

# Bump release version.
replace_once('pubspec.yaml', 'version: 0.5.4+20', 'version: 0.5.5+21')

print('Applied read-only checkpoint NFC provisioning; version 0.5.5+21')
