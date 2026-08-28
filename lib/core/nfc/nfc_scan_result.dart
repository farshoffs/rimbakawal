class NfcScanResult {
  const NfcScanResult({
    required this.tagId,
    required this.scannedAt,
    required this.technology,
    this.ndefPayload,
  });

  final String tagId;
  final DateTime scannedAt;
  final String technology;
  final String? ndefPayload;
}
