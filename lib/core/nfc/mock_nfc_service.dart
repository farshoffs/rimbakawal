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
