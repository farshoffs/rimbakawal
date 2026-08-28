import 'nfc_scan_result.dart';

abstract interface class NfcService {
  Future<bool> isAvailable();
  Future<NfcScanResult> scan();
}
