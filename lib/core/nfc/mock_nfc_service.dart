import 'dart:math';

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
