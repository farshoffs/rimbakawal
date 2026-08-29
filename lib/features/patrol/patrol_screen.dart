import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:torch_light/torch_light.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../../core/offline/offline_models.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/offline_sync_service.dart';

class PatrolScreen extends StatefulWidget {
  const PatrolScreen({
    required this.user,
    required this.nfcService,
    required this.mockMode,
    required this.api,
    super.key,
  });

  final AppUser user;
  final NfcService nfcService;
  final bool mockMode;
  final ApiService api;

  @override
  State<PatrolScreen> createState() => _PatrolScreenState();
}

class _PatrolScreenState extends State<PatrolScreen> {
  final OfflineStore _store = OfflineStore.instance;
  final OfflineSyncService _sync = OfflineSyncService.instance;
  final ImagePicker _imagePicker = ImagePicker();

  late final String _clientSessionId;
  late final DateTime _startedAt;
  StreamSubscription<Position>? _positionSub;
  Timer? _locationHeartbeat;
  OfflineBootstrap? _bootstrap;
  Position? _latestPosition;
  DateTime? _lastLocationSentAt;
  bool _scanning = false;
  bool _ending = false;
  bool _torchOn = false;
  bool _torchChanging = false;
  bool _liveStarting = true;
  String _locationStatus = 'Mencari lokasi…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _clientSessionId = _store.newId('patrol-session');
    unawaited(WakelockPlus.enable());
    _store.addListener(_onLocalChanged);
    _sync.addListener(_onLocalChanged);
    unawaited(_startOfflinePatrol());
  }

  @override
  void dispose() {
    _store.removeListener(_onLocalChanged);
    _sync.removeListener(_onLocalChanged);
    _positionSub?.cancel();
    _locationHeartbeat?.cancel();
    unawaited(WakelockPlus.disable());
    if (_torchOn && !kIsWeb) unawaited(TorchLight.disableTorch());
    if (!_ending) unawaited(widget.api.endLivePatrol(_clientSessionId));
    super.dispose();
  }

  void _onLocalChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startOfflinePatrol() async {
    await _store.queueEvent(
      userId: widget.user.id,
      type: 'patrol_start',
      occurredAt: _startedAt,
      payload: {'clientSessionId': _clientSessionId},
    );
    unawaited(_sync.syncNow());
    await _loadBootstrap();
    unawaited(_startLiveTracking());
  }

  Future<void> _loadBootstrap() async {
    try {
      final latest = await widget.api.getOfflineBootstrap();
      if (!mounted) return;
      setState(() => _bootstrap = latest);
    } catch (_) {
      final cached = _store.cachedBootstrap();
      if (!mounted) return;
      setState(() => _bootstrap = cached);
    }
  }

  Future<void> _startLiveTracking() async {
    try {
      await widget.api.startLivePatrol(_clientSessionId, _startedAt);
    } catch (_) {
      // Live map is best effort. Field work remains available offline.
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ApiException('Perkhidmatan lokasi dimatikan.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Benarkan lokasi untuk muncul pada peta rondaan langsung.',
        );
      }

      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await _handlePosition(initial, force: true);

      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen(
            (position) => unawaited(_handlePosition(position)),
            onError: (Object error) {
              if (!mounted) return;
              setState(() => _locationStatus = _cleanError(error));
            },
          );
      _locationHeartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        final position = _latestPosition;
        if (position != null) unawaited(_handlePosition(position, force: true));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _liveStarting = false;
        _locationStatus = _cleanError(error);
      });
    }
  }

  Future<void> _handlePosition(Position position, {bool force = false}) async {
    _latestPosition = position;
    final now = DateTime.now();
    if (!force &&
        _lastLocationSentAt != null &&
        now.difference(_lastLocationSentAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastLocationSentAt = now;
    try {
      await widget.api.updateLivePatrolLocation(
        _clientSessionId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      if (!mounted) return;
      setState(() {
        _liveStarting = false;
        _locationStatus =
            'LANGSUNG • ±${position.accuracy.round()} m • ${_clock(now)}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liveStarting = false;
        _locationStatus =
            'Lokasi tersedia • peta langsung menunggu sambungan internet • ±${position.accuracy.round()} m';
      });
    }
  }

  Future<Map<String, dynamic>?> _captureEventLocation() async {
    final current = _latestPosition;
    if (current != null) {
      return {
        'latitude': current.latitude,
        'longitude': current.longitude,
        'accuracy': current.accuracy,
      };
    }
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _scanCheckpoint() async {
    if (_scanning) return;
    final bootstrap = _bootstrap ?? _store.cachedBootstrap();
    if (bootstrap == null) {
      setState(() {
        _error = 'Konfigurasi rondaan belum pernah dimuat turun. Sambungkan peranti ke Internet sekali untuk menyediakan penggunaan luar talian.';
      });
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      if (!await widget.nfcService.isAvailable()) {
        throw StateError('NFC tidak tersedia pada telefon ini.');
      }
      final raw = await widget.nfcService.scan();
      final uid = _normalizeUid(raw.tagId);
      final checkpoint = bootstrap.checkpoints
          .where((item) => _normalizeUid(item.nfcUid) == uid)
          .firstOrNull;
      if (checkpoint == null) {
        throw const ApiException(
          'Tag ini bukan checkpoint aktif untuk Jabatan anda.',
        );
      }

      final sessionIndex = _sessionIndex(
        DateTime.now(),
        bootstrap.sessionIntervalMinutes,
        bootstrap.sessionStartMinutes,
      );
      final dayKey = _scheduleDayKey(
        DateTime.now(),
        bootstrap.sessionStartMinutes,
      );
      final localScans = _currentSessionScanEvents(
        sessionIndex: sessionIndex,
        dayKey: dayKey,
      );
      final completedIds = localScans
          .map((event) => (event.payload['checkpointId'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      if (completedIds.contains(checkpoint.id)) {
        throw ApiException('${checkpoint.name} sudah direkod dalam sesi ini.');
      }
      if (bootstrap.routeOrderEnforced) {
        final next = bootstrap.checkpoints
            .where((item) => !completedIds.contains(item.id))
            .firstOrNull;
        if (next != null && next.id != checkpoint.id) {
          throw ApiException('Checkpoint seterusnya ialah ${next.name}.');
        }
      }

      final occurredAt = DateTime.now();
      await _store.queueEvent(
        userId: widget.user.id,
        type: 'scan',
        occurredAt: occurredAt,
        location: await _captureEventLocation(),
        payload: {
          'clientSessionId': _clientSessionId,
          'nfcUid': uid,
          'checkpointId': checkpoint.id,
          'checkpointName': checkpoint.name,
          'sessionIndex': sessionIndex,
          'dayKey': dayKey,
        },
      );
      unawaited(_sync.syncNow());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${checkpoint.name} telah disimpan pada peranti dan akan disegerakkan secara automatik.',
          ),
        ),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _reportIncident(CachedCheckpoint? checkpoint) async {
    final noteController = TextEditingController();
    final photos = <_IncidentPhoto>[];
    String category = 'Keselamatan';
    String severity = 'normal';
    String? dialogError;

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            checkpoint == null
                ? 'Lapor Insiden'
                : 'Lapor Insiden • ${checkpoint.name}',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: const [
                      DropdownMenuItem(
                        value: 'Keselamatan',
                        child: Text('Keselamatan'),
                      ),
                      DropdownMenuItem(
                        value: 'Kerosakan',
                        child: Text('Kerosakan'),
                      ),
                      DropdownMenuItem(
                        value: 'Kebersihan',
                        child: Text('Kebersihan'),
                      ),
                      DropdownMenuItem(value: 'Akses', child: Text('Akses')),
                      DropdownMenuItem(
                        value: 'Lain-lain',
                        child: Text('Lain-lain'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => category = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: severity,
                    decoration: const InputDecoration(labelText: 'Keutamaan'),
                    items: const [
                      DropdownMenuItem(value: 'normal', child: Text('Biasa')),
                      DropdownMenuItem(
                        value: 'important',
                        child: Text('Penting'),
                      ),
                      DropdownMenuItem(value: 'urgent', child: Text('Segera')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => severity = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Catatan',
                      hintText: 'Apa yang anda jumpa?',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: photos.length >= 4
                            ? null
                            : () async {
                                try {
                                  final picked = await _pickIncidentPhotos(
                                    camera: true,
                                    remaining: 4 - photos.length,
                                  );
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    photos.addAll(picked);
                                    dialogError = null;
                                  });
                                } catch (error) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(
                                    () => dialogError = _cleanError(error),
                                  );
                                }
                              },
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Kamera'),
                      ),
                      OutlinedButton.icon(
                        onPressed: photos.length >= 4
                            ? null
                            : () async {
                                try {
                                  final picked = await _pickIncidentPhotos(
                                    camera: false,
                                    remaining: 4 - photos.length,
                                  );
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    photos.addAll(picked);
                                    dialogError = null;
                                  });
                                } catch (error) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(
                                    () => dialogError = _cleanError(error),
                                  );
                                }
                              },
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Galeri'),
                      ),
                    ],
                  ),
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        photos.length,
                        (index) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                photos[index].bytes,
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: -9,
                              top: -9,
                              child: IconButton.filled(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setDialogState(
                                  () => photos.removeAt(index),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.save_rounded),
              label: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    final note = noteController.text.trim();
    noteController.dispose();
    if (submit != true || note.isEmpty) return;

    await _store.queueEvent(
      userId: widget.user.id,
      type: 'incident',
      location: await _captureEventLocation(),
      payload: {
        'checkpointId': checkpoint?.id,
        'category': category,
        'severity': severity,
        'note': note,
        'images': photos.map((photo) => photo.dataUrl).toList(),
      },
    );
    unawaited(_sync.syncNow());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Insiden telah disimpan pada peranti dan akan disegerakkan secara automatik.',
        ),
      ),
    );
  }

  Future<void> _welfareCheck() async {
    await _store.queueEvent(
      userId: widget.user.id,
      type: 'welfare_check',
      location: await _captureEventLocation(),
      payload: const {
        'status': 'ok',
        'note': 'Pengawal mengesahkan keadaan selamat',
      },
    );
    unawaited(_sync.syncNow());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Status “Saya OK” disimpan.')));
  }

  Future<void> _toggleTorch() async {
    if (_torchChanging) return;
    setState(() => _torchChanging = true);
    try {
      if (kIsWeb) {
        throw const ApiException(
          'Lampu suluh hanya tersedia dalam aplikasi Android atau iOS.',
        );
      }
      if (_torchOn) {
        await TorchLight.disableTorch();
      } else {
        final available = await TorchLight.isTorchAvailable();
        if (!available) {
          throw const ApiException(
            'Lampu suluh tidak tersedia pada peranti ini.',
          );
        }
        await TorchLight.enableTorch();
      }
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_cleanError(error))));
    } finally {
      if (mounted) setState(() => _torchChanging = false);
    }
  }

  Future<void> _turnOffTorch() async {
    if (!_torchOn || kIsWeb) return;
    try {
      await TorchLight.disableTorch();
    } catch (_) {
      // Best effort when leaving the patrol screen.
    }
    if (mounted) setState(() => _torchOn = false);
  }

  Future<void> _finishPatrol() async {
    if (_ending) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tamatkan rondaan?'),
        content: Text(
          'Semua data telah disimpan pada peranti. ${_store.pendingCount(widget.user.id)} rekod masih menunggu penyegerakan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Teruskan ronda'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tamat Rondaan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _ending = true);
    await _store.queueEvent(
      userId: widget.user.id,
      type: 'patrol_end',
      payload: {'clientSessionId': _clientSessionId},
      location: await _captureEventLocation(),
    );
    unawaited(_sync.syncNow());
    try {
      await widget.api.endLivePatrol(_clientSessionId);
    } catch (_) {}
    await _turnOffTorch();
    await _positionSub?.cancel();
    _locationHeartbeat?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<List<_IncidentPhoto>> _pickIncidentPhotos({
    required bool camera,
    required int remaining,
  }) async {
    final files = <XFile>[];
    if (camera) {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 58,
        requestFullMetadata: false,
      );
      if (file != null) files.add(file);
    } else {
      files.addAll(
        await _imagePicker.pickMultiImage(
          maxWidth: 1000,
          maxHeight: 1000,
          imageQuality: 58,
          requestFullMetadata: false,
        ),
      );
    }

    final photos = <_IncidentPhoto>[];
    for (final file in files.take(remaining)) {
      final mime = _imageMimeType(file);
      if (mime == null) continue;
      final bytes = await file.readAsBytes();
      if (bytes.length > 350000) {
        throw const ApiException('Gambar terlalu besar. Cuba gambar lain.');
      }
      photos.add(
        _IncidentPhoto(
          bytes: bytes,
          dataUrl: 'data:$mime;base64,${base64Encode(bytes)}',
        ),
      );
    }
    return photos;
  }

  String? _imageMimeType(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp') {
      return mime;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  List<OfflineEvent> _currentSessionScanEvents({
    required int sessionIndex,
    required String dayKey,
  }) => _store.eventsForUser(widget.user.id, limit: 1000).where((event) {
        return event.type == 'scan' &&
            event.payload['clientSessionId'] == _clientSessionId &&
            event.payload['sessionIndex'] == sessionIndex &&
        event.payload['dayKey'] == dayKey &&
        !event.isFailed;
  }).toList();

  CachedCheckpoint? _nextCheckpoint(OfflineBootstrap bootstrap) {
    final index = _sessionIndex(
      DateTime.now(),
      bootstrap.sessionIntervalMinutes,
      bootstrap.sessionStartMinutes,
    );
    final day = _scheduleDayKey(DateTime.now(), bootstrap.sessionStartMinutes);
    final scannedIds =
        _currentSessionScanEvents(sessionIndex: index, dayKey: day)
            .map((event) => (event.payload['checkpointId'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
    return bootstrap.checkpoints
        .where((checkpoint) => !scannedIds.contains(checkpoint.id))
        .firstOrNull;
  }

  int _completedCount(OfflineBootstrap bootstrap) {
    final index = _sessionIndex(
      DateTime.now(),
      bootstrap.sessionIntervalMinutes,
      bootstrap.sessionStartMinutes,
    );
    final day = _scheduleDayKey(DateTime.now(), bootstrap.sessionStartMinutes);
    return _currentSessionScanEvents(sessionIndex: index, dayKey: day)
        .map((event) => (event.payload['checkpointId'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .length;
  }

  _SessionWindow _sessionWindow(
    DateTime value,
    int interval,
    int startMinutes,
  ) {
    final local = value.toLocal();
    final safeInterval = interval.clamp(15, 1440);
    final safeStart = startMinutes.clamp(0, 1439);
    var anchor = DateTime(
      local.year,
      local.month,
      local.day,
    ).add(Duration(minutes: safeStart));
    if (local.isBefore(anchor))
      anchor = anchor.subtract(const Duration(days: 1));
    final index = local.difference(anchor).inMinutes ~/ safeInterval;
    final start = anchor.add(Duration(minutes: index * safeInterval));
    final dayEnd = anchor.add(const Duration(days: 1));
    final rawEnd = start.add(Duration(minutes: safeInterval));
    final end = rawEnd.isAfter(dayEnd) ? dayEnd : rawEnd;
    return _SessionWindow(index: index, start: start, end: end);
  }

  int _sessionIndex(DateTime value, int interval, int startMinutes) =>
      _sessionWindow(value, interval, startMinutes).index;

  String _scheduleDayKey(DateTime value, int startMinutes) {
    final local = value.toLocal();
    final safeStart = startMinutes.clamp(0, 1439);
    var anchor = DateTime(
      local.year,
      local.month,
      local.day,
    ).add(Duration(minutes: safeStart));
    if (local.isBefore(anchor))
      anchor = anchor.subtract(const Duration(days: 1));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${anchor.year}-${two(anchor.month)}-${two(anchor.day)}';
  }

  String _hm(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _clock(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _normalizeUid(String value) =>
      value.trim().toUpperCase().replaceAll(' ', '');

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('TimeoutException: ', '')
      .replaceFirst('ApiException: ', '');

  ImageProvider<Object>? _profileImage() {
    final picture = widget.user.profilePicture;
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/') && picture.contains(',')) {
      try {
        return MemoryImage(base64Decode(picture.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(picture);
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = _bootstrap ?? _store.cachedBootstrap();
    final pending = _store.pendingCount(widget.user.id);
    final failed = _store.failedCount(widget.user.id);
    final completed = bootstrap == null ? 0 : _completedCount(bootstrap);
    final total = bootstrap?.checkpoints.length ?? 0;
    final progress = total == 0 ? 0.0 : completed / total;
    final next = bootstrap == null ? null : _nextCheckpoint(bootstrap);
    final activeSession = bootstrap == null
        ? null
        : _sessionWindow(
            DateTime.now(),
            bootstrap.sessionIntervalMinutes,
            bootstrap.sessionStartMinutes,
          );
    final sessionLabel = activeSession == null
        ? 'Sesi Rondaan belum tersedia'
        : 'Sesi Rondaan ${activeSession.index + 1} • ${_hm(activeSession.start)} – ${_hm(activeSession.end)}';
    final sessionEvents = bootstrap == null
        ? const <OfflineEvent>[]
        : _currentSessionScanEvents(
            sessionIndex: _sessionIndex(
              DateTime.now(),
              bootstrap.sessionIntervalMinutes,
              bootstrap.sessionStartMinutes,
            ),
            dayKey: _scheduleDayKey(
              DateTime.now(),
              bootstrap.sessionStartMinutes,
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rondaan Aktif'),
        actions: [
          IconButton(
            tooltip: 'Saya OK',
            onPressed: _welfareCheck,
            icon: const Icon(Icons.health_and_safety_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 66,
          child: FilledButton.icon(
            onPressed: _ending ? null : _finishPatrol,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6F2A25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.stop_circle_rounded, size: 30),
            label: Text(
              _ending ? 'MENAMATKAN RONDAAN…' : 'TAMAT RONDAAN',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.sizeOf(context).width - 32,
        height: 126,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'torch-fab',
              tooltip: _torchOn ? 'Tutup lampu suluh' : 'Buka lampu suluh',
              onPressed: _torchChanging || _ending ? null : _toggleTorch,
              backgroundColor: _torchOn
                  ? const Color(0xFFFFD54F)
                  : const Color(0xFF4834D4),
              foregroundColor: _torchOn
                  ? const Color(0xFF181818)
                  : Colors.white,
              child: Icon(
                _torchChanging
                    ? Icons.hourglass_top_rounded
                    : _torchOn
                    ? Icons.flashlight_off_rounded
                    : Icons.flashlight_on_rounded,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 66,
              child: FloatingActionButton.extended(
                heroTag: 'scan-checkpoint-fab',
                onPressed: _scanning || _ending ? null : _scanCheckpoint,
                elevation: 10,
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: const Color(0xFF181818),
                disabledElevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                ),
                icon: Icon(
                  _scanning ? Icons.radar_rounded : Icons.nfc_rounded,
                  size: 30,
                ),
                label: Text(
                  _scanning ? 'MENGIMBAS…' : 'IMBAS CHECKPOINT',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadBootstrap();
            await _sync.syncNow();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 178),
            children: [
              _LiveHero(
                user: widget.user,
                image: _profileImage(),
                locationStatus: _locationStatus,
                liveStarting: _liveStarting,
                pending: pending,
                failed: failed,
                syncing: _sync.isSyncing,
                onSync: _sync.syncNow,
              ),
              const SizedBox(height: 14),
              _RouteCard(
                department: bootstrap?.departmentName ?? widget.user.jabatan,
                completed: completed,
                total: total,
                progress: progress,
                next: next,
                interval:
                    bootstrap?.sessionIntervalMinutes ??
                    widget.user.sessionIntervalMinutes,
                sessionLabel: sessionLabel,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rekod sesi',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _reportIncident(next),
                    icon: const Icon(Icons.add_alert_rounded),
                    label: const Text('Insiden'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (sessionEvents.isEmpty)
                const _EmptyTimeline()
              else
                ...sessionEvents.reversed.map(
                  (event) => _TimelineEvent(
                    event: event,
                    checkpoint: bootstrap?.checkpoints
                        .where(
                          (item) =>
                              item.id ==
                              (event.payload['checkpointId'] as num?)?.toInt(),
                        )
                        .firstOrNull,
                    onIncident: () {
                      final checkpoint = bootstrap?.checkpoints
                          .where(
                            (item) =>
                                item.id ==
                                (event.payload['checkpointId'] as num?)
                                    ?.toInt(),
                          )
                          .firstOrNull;
                      _reportIncident(checkpoint);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionWindow {
  const _SessionWindow({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final DateTime start;
  final DateTime end;
}

class _LiveHero extends StatelessWidget {
  const _LiveHero({
    required this.user,
    required this.image,
    required this.locationStatus,
    required this.liveStarting,
    required this.pending,
    required this.failed,
    required this.syncing,
    required this.onSync,
  });

  final AppUser user;
  final ImageProvider<Object>? image;
  final String locationStatus;
  final bool liveStarting;
  final int pending;
  final int failed;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF251A4F), Color(0xFF151827), Color(0xFF341214)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: image,
                  child: image == null
                      ? Text(
                          user.nama.isEmpty ? '?' : user.nama[0],
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(user.jabatan),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B894).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  liveStarting ? 'MEMULAKAN' : 'SEDANG MERONDA',
                  style: const TextStyle(
                    color: Color(0xFF55E6C1),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.my_location_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  locationStatus,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _MiniBadge(
                icon: Icons.phone_android_rounded,
                text: 'DISIMPAN PADA PERANTI',
                color: Color(0xFF74B9FF),
              ),
              _MiniBadge(
                icon: syncing
                    ? Icons.sync_rounded
                    : Icons.cloud_upload_outlined,
                text: syncing ? 'MENYEGERAK…' : '$pending MENUNGGU',
                color: const Color(0xFFA29BFE),
              ),
              if (failed > 0)
                _MiniBadge(
                  icon: Icons.warning_amber_rounded,
                  text: '$failed GAGAL',
                  color: const Color(0xFFFF7675),
                ),
            ],
          ),
          if (pending > 0 || failed > 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: syncing ? null : onSync,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Segerak sekarang'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.department,
    required this.completed,
    required this.total,
    required this.progress,
    required this.next,
    required this.interval,
    required this.sessionLabel,
  });
  final String department;
  final int completed;
  final int total;
  final double progress;
  final CachedCheckpoint? next;
  final int interval;
  final String sessionLabel;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      department,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      sessionLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFA29BFE),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('Kadar: setiap $interval minit'),
                  ],
                ),
              ),
              Text(
                '$completed/$total',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.flag_circle_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SETERUSNYA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        next?.name ??
                            (total == 0
                                ? 'Tiada checkpoint aktif'
                                : 'Semua checkpoint selesai'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if ((next?.instruction ?? '').isNotEmpty)
                        Text(next!.instruction!),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.event,
    required this.checkpoint,
    required this.onIncident,
  });
  final OfflineEvent event;
  final CachedCheckpoint? checkpoint;
  final VoidCallback onIncident;

  @override
  Widget build(BuildContext context) {
    final color = event.isSynced
        ? const Color(0xFF55E6C1)
        : event.isFailed
        ? const Color(0xFFFF7675)
        : const Color(0xFFFFD166);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(
              event.isSynced
                  ? Icons.cloud_done_rounded
                  : event.isFailed
                  ? Icons.cloud_off_rounded
                  : Icons.phone_android_rounded,
              color: color,
            ),
          ),
          title: Text(
            checkpoint?.name ??
                event.payload['checkpointName'] as String? ??
                'Checkpoint',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${_formatEventTime(event.occurredAt)} • ${event.isSynced
                ? 'Disegerakkan'
                : event.isFailed
                ? 'Perlu semak'
                : 'Disimpan pada peranti'}',
          ),
          trailing: IconButton(
            tooltip: 'Lapor insiden',
            onPressed: onIncident,
            icon: const Icon(Icons.report_problem_outlined),
          ),
        ),
      ),
    );
  }

  static String _formatEventTime(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      child: Column(
        children: [
          Icon(
            Icons.route_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 10),
          const Text(
            'Belum ada checkpoint direkodkan dalam sesi ini.',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _IncidentPhoto {
  const _IncidentPhoto({required this.bytes, required this.dataUrl});
  final Uint8List bytes;
  final String dataUrl;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
