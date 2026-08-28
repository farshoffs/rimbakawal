import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class MockNfcService implements NfcService {
  final List<String> _mockTags = const [
    '04:A1:B2:C3:D4:E5:F6',
    '04:B2:C3:D4:E5:F6:07',
    '04:C3:D4:E5:F6:07:18',
  ];

  int _index = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<NfcScanResult> scan() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final tagId = _mockTags[_index % _mockTags.length];
    _index++;

    return NfcScanResult(
      tagId: tagId,
      scannedAt: DateTime.now(),
      ndefPayload: 'patrol://checkpoint/$tagId',
    );
  }
}
