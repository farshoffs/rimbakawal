import 'dart:math';

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
