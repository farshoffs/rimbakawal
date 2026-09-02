from pathlib import Path
import re


def write(path: str, content: str) -> None:
    Path(path).write_text(content, encoding='utf-8')


def patch_regex(path: str, pattern: str, replacement: str, *, flags: int = 0) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'Expected exactly one match in {path}: {pattern[:140]!r}; got {count}')
    file.write_text(updated, encoding='utf-8')


# NFC service contract: patrol scanning remains read-only, checkpoint setup gains an
# explicit rewrite/provision operation.
write('lib/core/nfc/nfc_service.dart', r'''import 'nfc_scan_result.dart';

class NfcScanCancelledException implements Exception {
  const NfcScanCancelledException();

  @override
  String toString() => 'Imbasan NFC dibatalkan.';
}

abstract interface class NfcService {
  Future<bool> isAvailable();
  Future<NfcScanResult> scan();
  Future<String> writeCheckpointTag({String? checkpointId});
  Future<void> cancelScan();
}
''')


write('lib/core/nfc/mock_nfc_service.dart', r'''import 'dart:math';

import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class MockNfcService implements NfcService {
  final List<String> _mockTags = const [
    'TEXT:CHECKPOINT-A',
    'TEXT:CHECKPOINT-B',
    '04:C3:D4:E5:F6:07:18',
  ];

  int _index = 0;
  int _scanGeneration = 0;
  String? _lastWrittenCheckpointId;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<NfcScanResult> scan() async {
    final generation = ++_scanGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (generation != _scanGeneration) {
      throw const NfcScanCancelledException();
    }

    final tagId = _lastWrittenCheckpointId ?? _mockTags[_index % _mockTags.length];
    _index++;

    return NfcScanResult(
      tagId: tagId,
      scannedAt: DateTime.now(),
      technology: 'NFC-A (mock)',
      ndefPayload: tagId.startsWith('RK-') ? tagId : null,
    );
  }

  @override
  Future<String> writeCheckpointTag({String? checkpointId}) async {
    final generation = ++_scanGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (generation != _scanGeneration) {
      throw const NfcScanCancelledException();
    }

    final existing = checkpointId?.trim().toUpperCase();
    final id = existing != null && existing.startsWith('RK-') && existing.length >= 12
        ? existing
        : _newCheckpointId();
    _lastWrittenCheckpointId = id;

    // Simulate the read-back verification performed by the real service.
    final readBack = await scan();
    if (readBack.tagId.toUpperCase() != id) {
      throw StateError('Pengesahan tag selepas ditulis gagal.');
    }
    return id;
  }

  String _newCheckpointId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'RK-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  @override
  Future<void> cancelScan() async {
    _scanGeneration++;
  }
}
''')


real_path = Path('lib/core/nfc/real_nfc_service.dart')
real = real_path.read_text(encoding='utf-8')
if "import 'dart:math';" not in real:
    real = real.replace("import 'dart:convert';\n", "import 'dart:convert';\nimport 'dart:math';\n")

# Remove a previous writer implementation if this script is re-run, then insert
# the current rewrite + read-back verified implementation.
real = re.sub(
    r"\n  @override\n  Future<String> writeCheckpointTag\(.*?\n  void _beginOperation",
    "\n  void _beginOperation",
    real,
    count=1,
    flags=re.S,
)
writer_method = r'''

  @override
  Future<String> writeCheckpointTag({String? checkpointId}) async {
    final completer = Completer<String>();
    _beginOperation(completer);
    var discoveryHandled = false;
    Timer? timeoutTimer;

    final requested = checkpointId?.trim().toUpperCase();
    final id = requested != null &&
            requested.startsWith('RK-') &&
            requested.length >= 12
        ? requested
        : _newCheckpointId();
    final message = _checkpointMessage(id);

    unawaited(
      completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );

    try {
      await _manager.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        alertMessageIos:
            'Dekatkan bahagian atas iPhone pada tag. Kandungan tag akan ditulis semula untuk RimbaKawal.',
        invalidateAfterFirstReadIos: true,
        onDiscovered: (tag) async {
          if (completer.isCompleted || discoveryHandled) return;
          discoveryHandled = true;
          try {
            await _writeAndVerifyCheckpointMessage(tag, message, id);
            await _stopQuietly(
              alertMessage: 'Tag RimbaKawal berjaya ditulis dan disahkan.',
            );
            if (!completer.isCompleted) completer.complete(id);
          } catch (error, stackTrace) {
            await _stopQuietly(
              errorMessage: 'Tag NFC tidak dapat ditulis atau disahkan.',
            );
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(
          completer,
          'Tiada tag NFC dikesan dalam masa 30 saat.',
        );
      }
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      _endOperation(completer);
    }
  }
'''
anchor = '\n  void _beginOperation(Completer<Object?> completer) {'
if anchor not in real:
    raise SystemExit('Could not locate NFC operation anchor in real_nfc_service.dart')
real = real.replace(anchor, writer_method + anchor, 1)

# Remove prior helper block if present, then add the current helper block before
# the iOS error handler. Existing scan normalization is deliberately preserved.
real = re.sub(
    r"\n  NdefMessage _checkpointMessage\(.*?(?=\n  void _completeIosError)",
    '',
    real,
    count=1,
    flags=re.S,
)
helpers = r'''

  NdefMessage _checkpointMessage(String checkpointId) {
    return NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.external,
          type: Uint8List.fromList(utf8.encode(_checkpointRecordType)),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(utf8.encode(checkpointId)),
        ),
      ],
    );
  }

  Future<void> _writeAndVerifyCheckpointMessage(
    NfcTag tag,
    NdefMessage message,
    String checkpointId,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        if (!ndef.isWritable) {
          throw StateError('Tag NFC ini dikunci atau read-only.');
        }
        if (message.byteLength > ndef.maxSize) {
          throw StateError('Kapasiti tag NFC tidak mencukupi.');
        }
        await ndef.writeNdefMessage(message);
        final readBack = await ndef.getNdefMessage();
        _verifyCheckpointReadBack(readBack, checkpointId);
        return;
      }

      final formatable = NdefFormatableAndroid.from(tag);
      if (formatable != null) {
        await formatable.format(message);
        // Some Android stacks do not expose Ndef on the same Tag object until
        // the next discovery after formatting. Formatting success is accepted.
        final ndefAfterFormat = NdefAndroid.from(tag);
        if (ndefAfterFormat != null) {
          final readBack = await ndefAfterFormat.getNdefMessage();
          _verifyCheckpointReadBack(readBack, checkpointId);
        }
        return;
      }
      throw StateError('Tag ini tidak menyokong penulisan NDEF.');
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) {
        throw StateError(
          'Tag ini tidak menyokong penulisan NDEF pada iPhone.',
        );
      }
      if (message.byteLength > ndef.capacity) {
        throw StateError('Kapasiti tag NFC tidak mencukupi.');
      }
      await ndef.writeNdef(message);
      final readBack = await ndef.readNdef();
      _verifyCheckpointReadBack(readBack, checkpointId);
      return;
    }

    throw UnsupportedError(
      'Penulisan NFC hanya tersedia pada Android dan iOS.',
    );
  }

  void _verifyCheckpointReadBack(
    NdefMessage? message,
    String checkpointId,
  ) {
    final readBack = _readOnlyIdFromMessage(message)?.toUpperCase();
    if (readBack != checkpointId.toUpperCase()) {
      throw StateError(
        'Tag telah disentuh tetapi ID RimbaKawal gagal dibaca semula. Cuba tag sekali lagi.',
      );
    }
  }

  String _newCheckpointId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'RK-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }
'''
error_anchor = '\n  void _completeIosError<T>('
if error_anchor not in real:
    raise SystemExit('Could not locate iOS error anchor in real_nfc_service.dart')
real = real.replace(error_anchor, helpers + error_anchor, 1)
real_path.write_text(real, encoding='utf-8')


screen_path = 'lib/features/admin/department_maintenance_screen.dart'
# Replace the current read-only scan handler with explicit rewrite + read-only
# helper actions. Patrol scan behavior elsewhere is not touched.
patch_regex(
    screen_path,
    r"  Future<void> _scanTag\(\) async \{.*?\n  Future<void> _save\(\) async \{",
    r'''  Future<void> _rewriteTag() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final available = await widget.nfcService.isAvailable();
      if (!available) {
        throw StateError('NFC tidak tersedia pada peranti ini.');
      }
      final current = _uidController.text.trim().toUpperCase();
      final checkpointId = await widget.nfcService.writeCheckpointTag(
        checkpointId: current.startsWith('RK-') ? current : null,
      );
      if (!mounted) return;
      setState(() => _uidController.text = checkpointId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tag berjaya ditulis semula, dibaca semula dan disahkan untuk checkpoint ini.',
          ),
        ),
      );
    } on NfcScanCancelledException {
      // User closed the native NFC prompt.
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _readTagOnly() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final available = await widget.nfcService.isAvailable();
      if (!available) {
        throw StateError('NFC tidak tersedia pada peranti ini.');
      }
      final scan = await widget.nfcService.scan();
      if (!mounted) return;
      setState(() => _uidController.text = scan.tagId.toUpperCase());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ID / UID dibaca: ${scan.tagId}'),
        ),
      );
    } on NfcScanCancelledException {
      // User closed the native NFC prompt.
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _save() async {''',
    flags=re.S,
)

screen = Path(screen_path).read_text(encoding='utf-8')
screen = screen.replace(
    "'Lengkapkan nama, Scan Tag dan susunan checkpoint.'",
    "'Lengkapkan nama, daftar tag NFC dan susunan checkpoint.'",
)
Path(screen_path).write_text(screen, encoding='utf-8')

# Replace the NFC field + old read-only button/explanation, keeping the existing
# mock-mode notice and the rest of the dialog intact.
patch_regex(
    screen_path,
    r"              TextField\(\n                controller: _uidController,.*?              if \(widget\.mockMode\) \.\.\.\[",
    r'''              TextField(
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
              ),
              if (widget.mockMode) ...[''',
    flags=re.S,
)

print('Checkpoint NFC writer v2 patch applied.')
