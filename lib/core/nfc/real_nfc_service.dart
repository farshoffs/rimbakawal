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

    unawaited(
      completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
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
            final result = await _normalizeTag(tag);
            await _stopQuietly(alertMessage: 'Checkpoint berjaya diimbas.');
            if (!completer.isCompleted) completer.complete(result);
          } catch (error, stackTrace) {
            await _stopQuietly(errorMessage: 'Tag NFC ini tidak dapat dibaca.');
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(
          completer,
          'Tiada tag NFC dikesan dalam masa 30 saat.',
        );
      }
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      _endOperation(completer);
    }
  }

  @override
  Future<String> writeCheckpointTag({String? checkpointId}) async {
    final completer = Completer<String>();
    _beginOperation(completer);
    var discoveryHandled = false;
    Timer? timeoutTimer;

    final requested = checkpointId?.trim().toUpperCase();
    final id =
        requested != null &&
            requested.startsWith('RK-') &&
            requested.length >= 12
        ? requested
        : _newCheckpointId();
    final message = _checkpointMessage(id);

    unawaited(
      completer.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );

    try {
      await _manager.startSession(
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        alertMessageIos: 'Dekatkan bahagian atas iPhone pada tag. Kandungan tag akan ditulis semula untuk RimbaKawal.',
        invalidateAfterFirstReadIos: true,
        onDiscovered: (tag) async {
          if (completer.isCompleted || discoveryHandled) return;
          discoveryHandled = true;
          try {
            await _writeAndVerifyCheckpointMessage(tag, message, id);
            await _stopQuietly(
              alertMessage: 'Tag RimbaKawal berjaya ditulis dan disahkan.',
            );
            if (!completer.isCompleted) completer.complete(id);
          } catch (error, stackTrace) {
            await _stopQuietly(
              errorMessage: 'Tag NFC tidak dapat ditulis atau disahkan.',
            );
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        onSessionErrorIos: (error) => _completeIosError(completer, error),
      );

      if (!completer.isCompleted) {
        timeoutTimer = _timeout(
          completer,
          'Tiada tag NFC dikesan dalam masa 30 saat.',
        );
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
    final ndefId = _readOnlyIdFromMessage(_cachedMessage(tag));

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag == null) {
        throw StateError('Android mengesan tag tetapi ID tidak dapat dibaca.');
      }
      return NfcScanResult(
        tagId: ndefId ?? _hex(androidTag.id),
        scannedAt: DateTime.now(),
        technology: androidTag.techList.isEmpty
            ? 'Android NFC'
            : androidTag.techList.join(', '),
        ndefPayload: ndefId,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (ndefId != null) {
        return NfcScanResult(
          tagId: ndefId,
          scannedAt: DateTime.now(),
          technology: 'iOS NDEF',
          ndefPayload: ndefId,
        );
      }
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

  String? _readOnlyIdFromMessage(NdefMessage? message) {
    if (message == null) return null;

    // Preserve compatibility with tags written by older RimbaKawal builds.
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.external) continue;
      final type = utf8.decode(record.type, allowMalformed: true).toLowerCase();
      if (type != _checkpointRecordType) continue;
      final value = utf8.decode(record.payload, allowMalformed: true).trim();
      if (value.isNotEmpty) return value.toUpperCase();
    }

    // NFC Tools and similar apps commonly write NFC Forum Text or URI records.
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.wellKnown) continue;
      final type = utf8.decode(record.type, allowMalformed: true);
      if (type == 'T') {
        final value = _textRecordValue(record.payload);
        if (value != null && value.isNotEmpty) return _bounded('TEXT:$value');
      }
      if (type == 'U') {
        final value = _uriRecordValue(record.payload);
        if (value != null && value.isNotEmpty) return _bounded('URI:$value');
      }
    }

    // For another pre-written NDEF record, derive a stable read-only identifier
    // from its bytes. No tag content is modified.
    for (final record in message.records) {
      if (record.payload.isEmpty && record.type.isEmpty) continue;
      return 'NDEF:${_stableNdefFingerprint(record)}';
    }
    return null;
  }

  String? _textRecordValue(Uint8List payload) {
    if (payload.isEmpty) return null;
    final status = payload[0];
    final utf16 = (status & 0x80) != 0;
    final languageLength = status & 0x3F;
    final textStart = 1 + languageLength;
    if (utf16 || textStart >= payload.length) return null;
    return utf8.decode(payload.sublist(textStart), allowMalformed: true).trim();
  }

  String? _uriRecordValue(Uint8List payload) {
    if (payload.isEmpty) return null;
    const prefixes = <String>[
      '',
      'http://www.',
      'https://www.',
      'http://',
      'https://',
      'tel:',
      'mailto:',
      'ftp://anonymous:anonymous@',
      'ftp://ftp.',
      'ftps://',
      'sftp://',
      'smb://',
      'nfs://',
      'ftp://',
      'dav://',
      'news:',
      'telnet://',
      'imap:',
      'rtsp://',
      'urn:',
      'pop:',
      'sip:',
      'sips:',
      'tftp:',
      'btspp://',
      'btl2cap://',
      'btgoep://',
      'tcpobex://',
      'irdaobex://',
      'file://',
      'urn:epc:id:',
      'urn:epc:tag:',
      'urn:epc:pat:',
      'urn:epc:raw:',
      'urn:epc:',
      'urn:nfc:',
    ];
    final code = payload[0];
    final prefix = code < prefixes.length ? prefixes[code] : '';
    final rest = utf8.decode(payload.sublist(1), allowMalformed: true).trim();
    return '$prefix$rest';
  }

  String _bounded(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 120) return trimmed;
    return 'NDEF:${_fingerprintBytes(Uint8List.fromList(utf8.encode(trimmed)))}';
  }

  String _stableNdefFingerprint(NdefRecord record) {
    final bytes = Uint8List.fromList([
      ...record.type,
      0,
      ...record.identifier,
      0,
      ...record.payload,
    ]);
    return _fingerprintBytes(bytes);
  }

  String _fingerprintBytes(Uint8List bytes) {
    var a = 0x811C9DC5;
    var b = 0x9E3779B9;
    for (final byte in bytes) {
      a = ((a ^ byte) * 0x01000193) & 0xFFFFFFFF;
      b = ((b + byte + ((b << 6) & 0xFFFFFFFF) + (b >> 2))) & 0xFFFFFFFF;
    }
    String hex32(int value) =>
        value.toRadixString(16).padLeft(8, '0').toUpperCase();
    return '${hex32(a)}${hex32(b)}';
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

  Future<void> _writeAndVerifyCheckpointMessage(
    NfcTag tag,
    NdefMessage message,
    String checkpointId,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef != null) {
        if (!ndef.isWritable) {
          throw StateError('Tag NFC ini dikunci atau read-only.');
        }
        if (message.byteLength > ndef.maxSize) {
          throw StateError('Kapasiti tag NFC tidak mencukupi.');
        }
        await ndef.writeNdefMessage(message);
        final readBack = await ndef.getNdefMessage();
        _verifyCheckpointReadBack(readBack, checkpointId);
        return;
      }

      final formatable = NdefFormatableAndroid.from(tag);
      if (formatable != null) {
        await formatable.format(message);
        // Some Android stacks do not expose Ndef on the same Tag object until
        // the next discovery after formatting. Formatting success is accepted.
        final ndefAfterFormat = NdefAndroid.from(tag);
        if (ndefAfterFormat != null) {
          final readBack = await ndefAfterFormat.getNdefMessage();
          _verifyCheckpointReadBack(readBack, checkpointId);
        }
        return;
      }
      throw StateError('Tag ini tidak menyokong penulisan NDEF.');
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ndef = NdefIos.from(tag);
      if (ndef == null) {
        throw StateError('Tag ini tidak menyokong penulisan NDEF pada iPhone.');
      }
      if (message.byteLength > ndef.capacity) {
        throw StateError('Kapasiti tag NFC tidak mencukupi.');
      }
      await ndef.writeNdef(message);
      final readBack = await ndef.readNdef();
      _verifyCheckpointReadBack(readBack, checkpointId);
      return;
    }

    throw UnsupportedError(
      'Penulisan NFC hanya tersedia pada Android dan iOS.',
    );
  }

  void _verifyCheckpointReadBack(NdefMessage? message, String checkpointId) {
    final readBack = _readOnlyIdFromMessage(message)?.toUpperCase();
    if (readBack != checkpointId.toUpperCase()) {
      throw StateError(
        'Tag telah disentuh tetapi ID RimbaKawal gagal dibaca semula. Cuba tag sekali lagi.',
      );
    }
  }

  String _newCheckpointId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'RK-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  void _completeIosError<T>(
    Completer<T> completer,
    NfcReaderSessionErrorIos error,
  ) {
    if (completer.isCompleted) return;
    final message = error.toString();
    final normalized = message.toLowerCase().replaceAll(' ', '');
    if (normalized.contains('usercancel')) {
      completer.completeError(const NfcScanCancelledException());
    } else {
      completer.completeError(StateError(message));
    }
  }

  Future<void> _stopQuietly({
    String? alertMessage,
    String? errorMessage,
  }) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _manager.stopSession(
          alertMessageIos: alertMessage,
          errorMessageIos: errorMessage,
        );
      } else {
        await _manager.stopSession();
      }
    } catch (_) {}
  }

  String _hex(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
