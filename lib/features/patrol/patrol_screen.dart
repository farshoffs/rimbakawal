import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';

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

class _PatrolScreenState extends State<PatrolScreen>
    with SingleTickerProviderStateMixin {
  final List<NfcLog> _scans = [];
  final ImagePicker _imagePicker = ImagePicker();
  late Future<PatrolConfig> _configFuture;
  late final AnimationController _sonarController;
  Timer? _locationTimer;
  int? _patrolSessionId;
  bool _scanning = false;
  bool _updatingLocation = false;
  String _locationStatus = 'Mengaktifkan lokasi langsung…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _sonarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _refreshConfig();
    _startPatrol();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _sonarController.dispose();
    final sessionId = _patrolSessionId;
    if (sessionId != null) unawaited(widget.api.endPatrolSession(sessionId));
    super.dispose();
  }

  void _refreshConfig() {
    setState(() => _configFuture = widget.api.getPatrolConfig());
  }

  Future<void> _startPatrol() async {
    try {
      final sessionId = await widget.api.startPatrolSession();
      if (!mounted) return;
      setState(() => _patrolSessionId = sessionId);
      await _sendLocation();
      _locationTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _sendLocation(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationStatus = 'Lokasi belum dihantar: $error');
    }
  }

  Future<void> _sendLocation() async {
    final sessionId = _patrolSessionId;
    if (sessionId == null || _updatingLocation) return;
    _updatingLocation = true;
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
        throw const ApiException('Kebenaran lokasi diperlukan semasa rondaan.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await widget.api.updatePatrolLocation(
        sessionId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      if (!mounted) return;
      setState(() {
        _locationStatus =
            'Lokasi langsung aktif • ketepatan ±${position.accuracy.round()} m';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationStatus = _cleanError(error));
    } finally {
      _updatingLocation = false;
    }
  }

  Future<void> _scanCheckpoint() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      if (!await widget.nfcService.isAvailable()) {
        throw StateError(
          'NFC tidak tersedia. Pastikan telefon menyokong NFC dan NFC dihidupkan.',
        );
      }
      final raw = await widget.nfcService.scan();
      final saved = await widget.api.storeNfcScan(raw.tagId);
      if (!mounted) return;
      setState(() => _scans.insert(0, saved));
      _refreshConfig();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${saved.checkpointName ?? 'Checkpoint'} berjaya direkodkan.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
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
        throw const ApiException(
          'Salah satu gambar terlalu besar. Cuba gambar lain.',
        );
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

  Future<void> _reportIncident(NfcLog scan) async {
    final noteController = TextEditingController();
    final photos = <_IncidentPhoto>[];
    String category = 'Keselamatan';
    String severity = 'normal';
    String? dialogError;

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Lapor Insiden • ${scan.checkpointName ?? 'Checkpoint'}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
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
                      hintText: 'Terangkan insiden yang ditemui.',
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
                                    () => dialogError = error.toString(),
                                  );
                                }
                              },
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Ambil Gambar'),
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
                                    () => dialogError = error.toString(),
                                  );
                                }
                              },
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Pilih Gambar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${photos.length}/4 gambar'),
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        photos.length,
                        (index) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                photos[index].bytes,
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: -8,
                              top: -8,
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
                    const SizedBox(height: 8),
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
              icon: const Icon(Icons.send_rounded),
              label: const Text('Hantar'),
            ),
          ],
        ),
      ),
    );

    final note = noteController.text.trim();
    noteController.dispose();
    if (submit != true) return;
    if (note.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan catatan insiden.')),
      );
      return;
    }
    try {
      await widget.api.createIncident(
        checkpointId: scan.checkpointId,
        category: category,
        severity: severity,
        note: note,
        images: photos.map((photo) => photo.dataUrl).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photos.isEmpty
                ? 'Insiden dihantar ke Command Center.'
                : 'Insiden dan ${photos.length} gambar berjaya dihantar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('TimeoutException: ', '');

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  ImageProvider<Object>? _profileImage() {
    final picture = widget.user.profilePicture;
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) {
        return MemoryImage(base64Decode(picture.substring(comma + 1)));
      }
    }
    return NetworkImage(picture);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rondaan'),
        actions: [
          IconButton(
            tooltip: 'Refresh laluan',
            onPressed: _refreshConfig,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _PatrollingProfile(
              user: widget.user,
              image: _profileImage(),
              animation: _sonarController,
              locationStatus: _locationStatus,
              onRefreshLocation: _sendLocation,
            ),
            const SizedBox(height: 14),
            FutureBuilder<PatrolConfig>(
              future: _configFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(snapshot.error.toString()),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                final config = snapshot.data!;
                final total = config.checkpoints.length;
                final completed = config.completedCount;
                final progress = total == 0 ? 0.0 : completed / total;
                final next = config.nextCheckpoint;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          config.departmentName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sesi Rondaan ${config.sessionIndex + 1} • setiap ${config.sessionIntervalMinutes} minit',
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
                        Text('$completed / $total checkpoint selesai'),
                        const SizedBox(height: 12),
                        if (next != null)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(child: Text('${next.position}')),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'CHECKPOINT SETERUSNYA',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        next.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 17,
                                        ),
                                      ),
                                      if (next.instruction != null &&
                                          next.instruction!.isNotEmpty)
                                        Text(next.instruction!),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (total > 0)
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.verified_rounded,
                              color: Colors.green,
                            ),
                            title: Text(
                              'Semua checkpoint Sesi Rondaan ini selesai.',
                            ),
                          ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: config.checkpoints
                              .map(
                                (checkpoint) => Chip(
                                  avatar: Icon(
                                    checkpoint.completed
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 17,
                                  ),
                                  label: Text(
                                    '${checkpoint.position}. ${checkpoint.name}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 68,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _scanCheckpoint,
                icon: Icon(_scanning ? Icons.radar : Icons.nfc, size: 28),
                label: Text(
                  _scanning ? 'Menunggu NFC…' : 'Scan Checkpoint',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Checkpoint direkodkan (${_scans.length})',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_scans.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Belum ada checkpoint direkodkan dalam rondaan ini.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._scans.map(
                (scan) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.check_rounded),
                    ),
                    title: Text(scan.checkpointName ?? 'Checkpoint'),
                    subtitle: Text(_formatTime(scan.scannedAt)),
                    trailing: IconButton(
                      tooltip: 'Lapor insiden',
                      onPressed: () => _reportIncident(scan),
                      icon: const Icon(Icons.report_problem_outlined),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PatrollingProfile extends StatelessWidget {
  const _PatrollingProfile({
    required this.user,
    required this.image,
    required this.animation,
    required this.locationStatus,
    required this.onRefreshLocation,
  });

  final AppUser user;
  final ImageProvider<Object>? image;
  final Animation<double> animation;
  final String locationStatus;
  final VoidCallback onRefreshLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var index = 0; index < 3; index++)
                      Builder(
                        builder: (context) {
                          final phase = (animation.value + index / 3) % 1.0;
                          final size = 105 + phase * 82;
                          return Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.secondary
                                    .withValues(alpha: (1.0 - phase) * 0.42),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 58,
                        backgroundImage: image,
                        child: image == null
                            ? Text(
                                user.nama.isEmpty ? '?' : user.nama[0],
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              user.nama,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'RONDAAN AKTIF',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: onRefreshLocation,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.my_location_rounded, size: 18),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        locationStatus,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentPhoto {
  const _IncidentPhoto({required this.bytes, required this.dataUrl});

  final Uint8List bytes;
  final String dataUrl;
}
