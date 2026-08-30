from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Expected text not found in {path}: {old[:160]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


Path('lib/core/nfc/nfc_service.dart').write_text(r'''import 'nfc_scan_result.dart';

class NfcScanCancelledException implements Exception {
  const NfcScanCancelledException();

  @override
  String toString() => 'Imbasan NFC dibatalkan.';
}

abstract interface class NfcService {
  Future<bool> isAvailable();
  Future<NfcScanResult> scan();
  Future<String> writeCheckpointTag();
  Future<void> cancelScan();
}
''', encoding='utf-8')

Path('lib/core/nfc/mock_nfc_service.dart').write_text(r'''import 'dart:math';

import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class MockNfcService implements NfcService {
  final List<String> _mockTags = const [
    '04:A1:B2:C3:D4:E5:F6',
    '04:B2:C3:D4:E5:F6:07',
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
      ndefPayload: 'rimbakawal://checkpoint/$tagId',
    );
  }

  @override
  Future<String> writeCheckpointTag() async {
    final generation = ++_scanGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (generation != _scanGeneration) {
      throw const NfcScanCancelledException();
    }
    final random = Random();
    final id = 'RK-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
    _lastWrittenCheckpointId = id;
    return id;
  }

  @override
  Future<void> cancelScan() async {
    _scanGeneration++;
  }
}
''', encoding='utf-8')

Path('lib/core/nfc/real_nfc_service.dart').write_text(r'''import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class RealNfcService implements NfcService {
  RealNfcService({NfcManager? manager})
      : _manager = manager ?? NfcManager.instance;

  static const _checkpointRecordType = 'dev.rimbakawal:checkpoint';

  final NfcManager _manager;
  Completer<Object?>? _activeOperation;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final availability = await _manager.checkAvailability();
      return availability == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NfcScanResult> scan() async {
    final completer = Completer<NfcScanResult>();
    _beginOperation(completer);
    var discoveryHandled = false;
    Timer? timeoutTimer;

    unawaited(completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));

    try {
      await _manager.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        alertMessageIos: 'Dekatkan bahagian atas iPhone pada tag checkpoint.',
        invalidateAfterFirstReadIos: true,
        onDiscovered: (tag) async {
          if (completer.isCompleted || discoveryHandled) return;
          discoveryHandled = true;
          try {
            final result = await _normalizeTag(tag);
            await _stopQuietly(alertMessage: 'Checkpoint berjaya diimbas.');
            if (!completer.isCompleted) completer.complete(result);
          } catch (error, stackTrace) {
            await _stopQuietly(errorMessage: 'Tag NFC ini tidak dapat dibaca.');
            if (!completer.isCompleted) completer.completeError(error, stackTrace);
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(completer, 'Tiada tag NFC dikesan dalam masa 30 saat.');
      }
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      _endOperation(completer);
    }
  }

  @override
  Future<String> writeCheckpointTag() async {
    final completer = Completer<String>();
    _beginOperation(completer);
    var discoveryHandled = false;
    Timer? timeoutTimer;
    final checkpointId = _newCheckpointId();
    final message = _checkpointMessage(checkpointId);

    unawaited(completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));

    try {
      await _manager.startSession(
        pollingOptions: const {NfcPollingOption.iso14443},
        alertMessageIos: 'Dekatkan bahagian atas iPhone pada tag untuk menetapkan checkpoint.',
        invalidateAfterFirstReadIos: true,
        onDiscovered: (tag) async {
          if (completer.isCompleted || discoveryHandled) return;
          discoveryHandled = true;
          try {
            await _writeMessage(tag, message);
            await _stopQuietly(alertMessage: 'Tag checkpoint berjaya ditetapkan.');
            if (!completer.isCompleted) completer.complete(checkpointId);
          } catch (error, stackTrace) {
            await _stopQuietly(errorMessage: 'Tag NFC tidak dapat ditulis.');
            if (!completer.isCompleted) completer.completeError(error, stackTrace);
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(completer, 'Tiada tag NFC dikesan dalam masa 30 saat.');
      }
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      _endOperation(completer);
    }
  }

  void _beginOperation(Completer<Object?> completer) {
    final existing = _activeOperation;
    if (existing != null && !existing.isCompleted) {
      throw StateError('Operasi NFC sedang berjalan.');
    }
    _activeOperation = completer;
  }

  void _endOperation(Completer<Object?> completer) {
    if (identical(_activeOperation, completer)) _activeOperation = null;
  }

  Timer _timeout<T>(Completer<T> completer, String message) {
    return Timer(const Duration(seconds: 30), () async {
      if (completer.isCompleted) return;
      await _stopQuietly(errorMessage: 'Masa operasi NFC telah tamat.');
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(message));
      }
    });
  }

  @override
  Future<void> cancelScan() async {
    final completer = _activeOperation;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const NfcScanCancelledException());
    }
    await _stopQuietly();
  }

  Future<NfcScanResult> _normalizeTag(NfcTag tag) async {
    final checkpointId = _checkpointIdFromMessage(_cachedMessage(tag));

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag == null) {
        throw StateError('Android mengesan tag tetapi ID tidak dapat dibaca.');
      }
      return NfcScanResult(
        tagId: checkpointId ?? _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty ? 'Android NFC' : androidTag.techList.join(', '),
        ndefPayload: checkpointId == null ? null : 'rimbakawal://checkpoint/$checkpointId',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (checkpointId != null) {
        return NfcScanResult(
          tagId: checkpointId,
          scannedAt: DateTime.now(),
          technology: 'iOS NDEF',
          ndefPayload: 'rimbakawal://checkpoint/$checkpointId',
        );
      }
      final miFare = MiFareIos.from(tag);
      if (miFare != null) {
        return NfcScanResult(tagId: _hex(miFare.identifier), scannedAt: DateTime.now(), technology: 'iOS MiFare (${miFare.mifareFamily.name})');
      }
      final iso7816 = Iso7816Ios.from(tag);
      if (iso7816 != null) {
        return NfcScanResult(tagId: _hex(iso7816.identifier), scannedAt: DateTime.now(), technology: 'iOS ISO 7816');
      }
      final iso15693 = Iso15693Ios.from(tag);
      if (iso15693 != null) {
        return NfcScanResult(tagId: _hex(iso15693.identifier), scannedAt: DateTime.now(), technology: 'iOS ISO 15693');
      }
      throw StateError('iPhone mengesan tag tetapi ID tag tidak dapat dibaca.');
    }

    throw UnsupportedError('NFC sebenar hanya tersedia pada Android dan iOS.');
  }

  NdefMessage? _cachedMessage(NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return NdefAndroid.from(tag)?.cachedNdefMessage;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return NdefIos.from(tag)?.cachedNdefMessage;
    }
    return null;
  }

  String? _checkpointIdFromMessage(NdefMessage? message) {
    if (message == null) return null;
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.external) continue;
      final type = utf8.decode(record.type, allowMalformed: true).toLowerCase();
      if (type != _checkpointRecordType) continue;
      final value = utf8.decode(record.payload, allowMalformed: true).trim().toUpperCase();
      if (value.startsWith('RK-') && value.length >= 12) return value;
    }
    return null;
  }

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

  Future<void> _writeMessage(NfcTag tag, NdefMessage message) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        if (!ndef.isWritable) throw StateError('Tag NFC ini dikunci atau read-only.');
        if (message.byteLength > ndef.maxSize) throw StateError('Kapasiti tag NFC tidak mencukupi.');
        await ndef.writeNdefMessage(message);
        return;
      }
      final formatable = NdefFormatableAndroid.from(tag);
      if (formatable != null) {
        await formatable.format(message);
        return;
      }
      throw StateError('Tag ini tidak menyokong penulisan NDEF.');
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) throw StateError('Tag ini tidak menyokong penulisan NDEF pada iPhone.');
      if (message.byteLength > ndef.capacity) throw StateError('Kapasiti tag NFC tidak mencukupi.');
      await ndef.writeNdef(message);
      return;
    }

    throw UnsupportedError('Penulisan NFC hanya tersedia pada Android dan iOS.');
  }

  String _newCheckpointId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'RK-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  void _completeIosError<T>(Completer<T> completer, NfcReaderSessionErrorIos error) {
    if (completer.isCompleted) return;
    final message = error.toString();
    final normalized = message.toLowerCase().replaceAll(' ', '');
    if (normalized.contains('usercancel')) {
      completer.completeError(const NfcScanCancelledException());
    } else {
      completer.completeError(StateError(message));
    }
  }

  Future<void> _stopQuietly({String? alertMessage, String? errorMessage}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _manager.stopSession(alertMessageIos: alertMessage, errorMessageIos: errorMessage);
      } else {
        await _manager.stopSession();
      }
    } catch (_) {}
  }

  String _hex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }
}
''', encoding='utf-8')

replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "  Future<void> _scanUid() async {\n    if (_scanning) return;\n    setState(() {\n      _scanning = true;\n      _error = null;\n    });\n    try {\n      final result = await showNfcScanPrompt(\n        context: context,\n        nfcService: widget.nfcService,\n        title: 'Imbas UID Tag NFC',\n      );\n      if (result == null) return;\n      if (!mounted) return;\n      _uidController.text = result.tagId.toUpperCase();\n    } catch (error) {\n      if (!mounted) return;\n      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));\n    } finally {\n      if (mounted) setState(() => _scanning = false);\n    }\n  }",
    "  Future<void> _scanTag() async {\n    if (_scanning) return;\n    setState(() {\n      _scanning = true;\n      _error = null;\n    });\n    try {\n      final available = await widget.nfcService.isAvailable();\n      if (!available) {\n        throw StateError('NFC tidak tersedia pada peranti ini.');\n      }\n      final checkpointId = await widget.nfcService.writeCheckpointTag();\n      if (!mounted) return;\n      setState(() => _uidController.text = checkpointId);\n      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(content: Text('Tag NFC berjaya ditetapkan untuk checkpoint ini.')),\n      );\n    } on NfcScanCancelledException {\n      // User closed the native NFC prompt.\n    } catch (error) {\n      if (!mounted) return;\n      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));\n    } finally {\n      if (mounted) setState(() => _scanning = false);\n    }\n  }",
)
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "                        labelText: 'UID tag NFC',\n                        hintText: 'Imbas tag atau masukkan UID',",
    "                        labelText: 'ID tag NFC',\n                        hintText: 'Tekan Scan Tag untuk menetapkan tag',",
)
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "                      onPressed: _scanning ? null : _scanUid,\n                      icon: const Icon(Icons.nfc_rounded),\n                      label: Text(_scanning ? 'Mengimbas…' : 'Imbas'),",
    "                      onPressed: _scanning ? null : _scanTag,\n                      icon: const Icon(Icons.nfc_rounded),\n                      label: Text(_scanning ? 'Menulis…' : 'Scan Tag'),",
)
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "                    'Versi web menggunakan simulasi NFC untuk ujian konfigurasi.',",
    "                    'Versi web menggunakan simulasi penulisan NFC untuk ujian konfigurasi.',",
)
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "      setState(() => _error = 'Lengkapkan nama, UID tag NFC dan susunan checkpoint.');",
    "      setState(() => _error = 'Lengkapkan nama, Scan Tag dan susunan checkpoint.');",
)

print('Checkpoint NFC writer patch applied.')
