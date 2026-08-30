import 'dart:async';

import 'package:flutter/material.dart';

import 'nfc_scan_result.dart';
import 'nfc_service.dart';

Future<NfcScanResult?> showNfcScanPrompt({
  required BuildContext context,
  required NfcService nfcService,
  String title = 'Imbas NFC',
}) {
  return showDialog<NfcScanResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _NfcScanPrompt(
      nfcService: nfcService,
      title: title,
    ),
  );
}

class _NfcScanPrompt extends StatefulWidget {
  const _NfcScanPrompt({
    required this.nfcService,
    required this.title,
  });

  final NfcService nfcService;
  final String title;

  @override
  State<_NfcScanPrompt> createState() => _NfcScanPromptState();
}

class _NfcScanPromptState extends State<_NfcScanPrompt> {
  bool _busy = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_startScan());
  }

  @override
  void dispose() {
    if (!_closing) unawaited(widget.nfcService.cancelScan());
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_busy || _closing) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (!await widget.nfcService.isAvailable()) {
        throw StateError(
          'NFC tidak tersedia. Pastikan telefon menyokong NFC dan hidupkan NFC dalam Tetapan Android.',
        );
      }
      if (!mounted || _closing) return;

      final result = await widget.nfcService.scan();
      if (!mounted || _closing) return;
      _closing = true;
      Navigator.of(context).pop(result);
    } on NfcScanCancelledException {
      if (!mounted || _closing) return;
      _closing = true;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted || _closing) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_closing) return;
    setState(() => _closing = true);
    await widget.nfcService.cancelScan();
    if (mounted) Navigator.of(context).pop();
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('TimeoutException: ', '')
        .replaceFirst('PlatformException', 'Ralat NFC');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.nfc_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 54,
                          height: 54,
                          child: CircularProgressIndicator(strokeWidth: 5),
                        )
                      : Icon(
                          _error == null
                              ? Icons.nfc_rounded
                              : Icons.error_outline_rounded,
                          size: 54,
                          color: _error == null
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _error == null
                    ? 'Dekatkan bahagian belakang telefon pada tag checkpoint dan kekalkan sehingga berjaya.'
                    : _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _error == null ? null : colorScheme.error,
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 10),
                Text(
                  'Mengimbas…',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _closing ? null : _cancel,
            child: const Text('Batal'),
          ),
          if (_error != null)
            FilledButton.icon(
              onPressed: _busy || _closing ? null : _startScan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Cuba Lagi'),
            ),
        ],
      ),
    );
  }
}
