import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class RealNfcService implements NfcService {
  RealNfcService({NfcManager? manager})
      : _manager = manager ?? NfcManager.instance;

  final NfcManager _manager;
  Completer<NfcScanResult>? _activeScan;

  @override
  Future<bool> isAvailable() async {
    final availability = await _manager.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  @override
  Future<NfcScanResult> scan() async {
    final existingScan = _activeScan;
    if (existingScan != null && !existingScan.isCompleted) {
      throw StateError('Imbasan NFC sedang berjalan.');
    }

    final completer = Completer<NfcScanResult>();
    _activeScan = completer;
    var discoveryHandled = false;
    Timer? timeoutTimer;

    // Keep an error listener attached while startSession is still awaiting the
    // platform channel. This also makes a very early user cancellation safe.
    unawaited(
      completer.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );

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
            final result = _normalizeTag(tag);
            await _stopQuietly(alertMessage: 'Checkpoint berjaya diimbas.');
            if (!completer.isCompleted) completer.complete(result);
          } catch (error, stackTrace) {
            await _stopQuietly(
              errorMessage: 'Tag NFC ini tidak dapat dibaca.',
            );
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        onSessionErrorIos: (error) {
          if (completer.isCompleted) return;

          final message = error.toString();
          final normalized = message.toLowerCase().replaceAll(' ', '');
          if (normalized.contains('usercancel')) {
            completer.completeError(const NfcScanCancelledException());
          } else {
            completer.completeError(StateError(message));
          }
        },
      );

      if (completer.isCompleted) {
        await _stopQuietly();
      } else {
        timeoutTimer = Timer(const Duration(seconds: 30), () async {
          if (completer.isCompleted) return;
          await _stopQuietly(
            errorMessage: 'Masa imbasan NFC telah tamat.',
          );
          if (!completer.isCompleted) {
            completer.completeError(
              TimeoutException('Tiada tag NFC dikesan dalam masa 30 saat.'),
            );
          }
        });
      }

      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      if (identical(_activeScan, completer)) {
        _activeScan = null;
      }
    }
  }

  @override
  Future<void> cancelScan() async {
    final completer = _activeScan;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const NfcScanCancelledException());
    }
    await _stopQuietly();
  }

  NfcScanResult _normalizeTag(NfcTag tag) {
    if (Platform.isAndroid) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag == null) {
        throw StateError('Android mengesan tag tetapi ID tidak dapat dibaca.');
      }

      return NfcScanResult(
        tagId: _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty
            ? 'Android NFC'
            : androidTag.techList.join(', '),
      );
    }

    if (Platform.isIOS) {
      final miFare = MiFareIos.from(tag);
      if (miFare != null) {
        return NfcScanResult(
          tagId: _hex(miFare.identifier),
          scannedAt: DateTime.now(),
          technology: 'iOS MiFare (${miFare.mifareFamily.name})',
        );
      }

      final iso7816 = Iso7816Ios.from(tag);
      if (iso7816 != null) {
        return NfcScanResult(
          tagId: _hex(iso7816.identifier),
          scannedAt: DateTime.now(),
          technology: 'iOS ISO 7816',
        );
      }

      final iso15693 = Iso15693Ios.from(tag);
      if (iso15693 != null) {
        return NfcScanResult(
          tagId: _hex(iso15693.identifier),
          scannedAt: DateTime.now(),
          technology: 'iOS ISO 15693',
        );
      }

      throw StateError(
        'iPhone mengesan tag tetapi ID tag tidak dapat dibaca.',
      );
    }

    throw UnsupportedError('NFC sebenar hanya tersedia pada Android dan iOS.');
  }

  Future<void> _stopQuietly({
    String? alertMessage,
    String? errorMessage,
  }) async {
    try {
      if (Platform.isIOS) {
        await _manager.stopSession(
          alertMessageIos: alertMessage,
          errorMessageIos: errorMessage,
        );
      } else {
        await _manager.stopSession();
      }
    } catch (_) {
      // The OS may already have invalidated or closed the reader session.
    }
  }

  String _hex(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
