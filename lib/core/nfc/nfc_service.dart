import 'nfc_scan_result.dart';

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
