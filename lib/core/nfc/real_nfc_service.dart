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

  @override
  Future<bool> isAvailable() async {
    final availability = await _manager.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  @override
  Future<NfcScanResult> scan() async {
    final completer = Completer<NfcScanResult>();

    await _manager.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      alertMessageIos: 'Hold your iPhone near the patrol checkpoint tag.',
      invalidateAfterFirstReadIos: true,
      onDiscovered: (tag) async {
        if (completer.isCompleted) return;

        try {
          final result = _normalizeTag(tag);
          completer.complete(result);

          if (Platform.isAndroid) {
            await _manager.stopSession();
          } else if (Platform.isIOS) {
            await _manager.stopSession(alertMessageIos: 'Checkpoint scanned.');
          }
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
          await _stopQuietly(errorMessage: 'Unable to read this NFC tag.');
        }
      },
      onSessionErrorIos: (error) {
        if (!completer.isCompleted) {
          completer.completeError(StateError(error.toString()));
        }
      },
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      await _stopQuietly(errorMessage: 'NFC scan timed out.');
      throw TimeoutException('No NFC tag detected within 30 seconds.');
    }
  }

  NfcScanResult _normalizeTag(NfcTag tag) {
    if (Platform.isAndroid) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag == null) {
        throw StateError('Android detected a tag but could not read its ID.');
      }

      return NfcScanResult(
        tagId: _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty
            ? 'Android NFC / ISO 14443'
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
        'iPhone detected the NFC tag, but this prototype could not extract an identifier from it.',
      );
    }

    throw UnsupportedError('Real NFC is only enabled for Android and iOS.');
  }

  Future<void> _stopQuietly({String? errorMessage}) async {
    try {
      if (Platform.isIOS) {
        await _manager.stopSession(errorMessageIos: errorMessage);
      } else {
        await _manager.stopSession();
      }
    } catch (_) {
      // Session may already have been invalidated by the OS.
    }
  }

  String _hex(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
