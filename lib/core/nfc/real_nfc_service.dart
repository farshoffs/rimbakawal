import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'nfc_scan_result.dart';
import 'nfc_service.dart';

class RealNfcService implements NfcService {
  RealNfcService({NfcManager? manager})
      : _manager = manager ?? NfcManager.instance;

  static const _checkpointRecordType = 'dev.rimbakawal:checkpoint';

  final NfcManager _manager;
  Completer<Object?>? _activeOperation;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final availability = await _manager.checkAvailability();
      return availability == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NfcScanResult> scan() async {
    final completer = Completer<NfcScanResult>();
    _beginOperation(completer);
    var discoveryHandled = false;
    Timer? timeoutTimer;

    unawaited(completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));

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
            final result = await _normalizeTag(tag);
            await _stopQuietly(alertMessage: 'Checkpoint berjaya diimbas.');
            if (!completer.isCompleted) completer.complete(result);
          } catch (error, stackTrace) {
            await _stopQuietly(errorMessage: 'Tag NFC ini tidak dapat dibaca.');
            if (!completer.isCompleted) completer.completeError(error, stackTrace);
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(completer, 'Tiada tag NFC dikesan dalam masa 30 saat.');
      }
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      _endOperation(completer);
    }
  }

  @override
  Future<String> writeCheckpointTag() async {
    final completer = Completer<String>();
    _beginOperation(completer);
    var discoveryHandled = false;
    Timer? timeoutTimer;
    final checkpointId = _newCheckpointId();
    final message = _checkpointMessage(checkpointId);

    unawaited(completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));

    try {
      await _manager.startSession(
        pollingOptions: const {NfcPollingOption.iso14443},
        alertMessageIos: 'Dekatkan bahagian atas iPhone pada tag untuk menetapkan checkpoint.',
        invalidateAfterFirstReadIos: true,
        onDiscovered: (tag) async {
          if (completer.isCompleted || discoveryHandled) return;
          discoveryHandled = true;
          try {
            await _writeMessage(tag, message);
            await _stopQuietly(alertMessage: 'Tag checkpoint berjaya ditetapkan.');
            if (!completer.isCompleted) completer.complete(checkpointId);
          } catch (error, stackTrace) {
            await _stopQuietly(errorMessage: 'Tag NFC tidak dapat ditulis.');
            if (!completer.isCompleted) completer.completeError(error, stackTrace);
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(completer, 'Tiada tag NFC dikesan dalam masa 30 saat.');
      }
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      _endOperation(completer);
    }
  }

  void _beginOperation(Completer<Object?> completer) {
    final existing = _activeOperation;
    if (existing != null && !existing.isCompleted) {
      throw StateError('Operasi NFC sedang berjalan.');
    }
    _activeOperation = completer;
  }

  void _endOperation(Completer<Object?> completer) {
    if (identical(_activeOperation, completer)) _activeOperation = null;
  }

  Timer _timeout<T>(Completer<T> completer, String message) {
    return Timer(const Duration(seconds: 30), () async {
      if (completer.isCompleted) return;
      await _stopQuietly(errorMessage: 'Masa operasi NFC telah tamat.');
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(message));
      }
    });
  }

  @override
  Future<void> cancelScan() async {
    final completer = _activeOperation;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const NfcScanCancelledException());
    }
    await _stopQuietly();
  }

  Future<NfcScanResult> _normalizeTag(NfcTag tag) async {
    final checkpointId = _checkpointIdFromMessage(_cachedMessage(tag));

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag == null) {
        throw StateError('Android mengesan tag tetapi ID tidak dapat dibaca.');
      }
      return NfcScanResult(
        tagId: checkpointId ?? _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty ? 'Android NFC' : androidTag.techList.join(', '),
        ndefPayload: checkpointId == null ? null : 'rimbakawal://checkpoint/$checkpointId',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (checkpointId != null) {
        return NfcScanResult(
          tagId: checkpointId,
          scannedAt: DateTime.now(),
          technology: 'iOS NDEF',
          ndefPayload: 'rimbakawal://checkpoint/$checkpointId',
        );
      }
      final miFare = MiFareIos.from(tag);
      if (miFare != null) {
        return NfcScanResult(tagId: _hex(miFare.identifier), scannedAt: DateTime.now(), technology: 'iOS MiFare (${miFare.mifareFamily.name})');
      }
      final iso7816 = Iso7816Ios.from(tag);
      if (iso7816 != null) {
        return NfcScanResult(tagId: _hex(iso7816.identifier), scannedAt: DateTime.now(), technology: 'iOS ISO 7816');
      }
      final iso15693 = Iso15693Ios.from(tag);
      if (iso15693 != null) {
        return NfcScanResult(tagId: _hex(iso15693.identifier), scannedAt: DateTime.now(), technology: 'iOS ISO 15693');
      }
      throw StateError('iPhone mengesan tag tetapi ID tag tidak dapat dibaca.');
    }

    throw UnsupportedError('NFC sebenar hanya tersedia pada Android dan iOS.');
  }

  NdefMessage? _cachedMessage(NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return NdefAndroid.from(tag)?.cachedNdefMessage;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return NdefIos.from(tag)?.cachedNdefMessage;
    }
    return null;
  }

  String? _checkpointIdFromMessage(NdefMessage? message) {
    if (message == null) return null;
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.external) continue;
      final type = utf8.decode(record.type, allowMalformed: true).toLowerCase();
      if (type != _checkpointRecordType) continue;
      final value = utf8.decode(record.payload, allowMalformed: true).trim().toUpperCase();
      if (value.startsWith('RK-') && value.length >= 12) return value;
    }
    return null;
  }

  NdefMessage _checkpointMessage(String checkpointId) {
    return NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.external,
          type: Uint8List.fromList(utf8.encode(_checkpointRecordType)),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(utf8.encode(checkpointId)),
        ),
      ],
    );
  }

  Future<void> _writeMessage(NfcTag tag, NdefMessage message) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        if (!ndef.isWritable) throw StateError('Tag NFC ini dikunci atau read-only.');
        if (message.byteLength > ndef.maxSize) throw StateError('Kapasiti tag NFC tidak mencukupi.');
        await ndef.writeNdefMessage(message);
        return;
      }
      final formatable = NdefFormatableAndroid.from(tag);
      if (formatable != null) {
        await formatable.format(message);
        return;
      }
      throw StateError('Tag ini tidak menyokong penulisan NDEF.');
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) throw StateError('Tag ini tidak menyokong penulisan NDEF pada iPhone.');
      if (message.byteLength > ndef.capacity) throw StateError('Kapasiti tag NFC tidak mencukupi.');
      await ndef.writeNdef(message);
      return;
    }

    throw UnsupportedError('Penulisan NFC hanya tersedia pada Android dan iOS.');
  }

  String _newCheckpointId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'RK-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  void _completeIosError<T>(Completer<T> completer, NfcReaderSessionErrorIos error) {
    if (completer.isCompleted) return;
    final message = error.toString();
    final normalized = message.toLowerCase().replaceAll(' ', '');
    if (normalized.contains('usercancel')) {
      completer.completeError(const NfcScanCancelledException());
    } else {
      completer.completeError(StateError(message));
    }
  }

  Future<void> _stopQuietly({String? alertMessage, String? errorMessage}) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _manager.stopSession(alertMessageIos: alertMessage, errorMessageIos: errorMessage);
      } else {
        await _manager.stopSession();
      }
    } catch (_) {}
  }

  String _hex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }
}
