import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'web_selfie_capture_stub.dart'
    if (dart.library.html) 'web_selfie_capture_web.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({required this.api, required this.user, super.key});

  final ApiService api;
  final AppUser user;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final ImagePicker _picker = ImagePicker();
  AttendanceStatus? _status;
  bool _loading = true;
  bool _punching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final status = await widget.api.getAttendanceStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Aktifkan Location/GPS sebelum punch kehadiran.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Kebenaran lokasi diperlukan untuk kehadiran.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _punch() async {
    if (_punching) return;
    setState(() {
      _punching = true;
      _error = null;
    });
    try {
      final position = await _currentPosition();
      if (!mounted) return;
      final String? dataUrl;
      if (kIsWeb) {
        dataUrl = await captureWebSelfie(context);
      } else {
        final image = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          maxWidth: 720,
          imageQuality: 65,
        );
        if (image == null) return;
        final bytes = await image.readAsBytes();
        final lower = image.path.toLowerCase();
        final mime = lower.endsWith('.png') ? 'png' : 'jpeg';
        dataUrl = 'data:image/$mime;base64,${base64Encode(bytes)}';
      }
      if (dataUrl == null || dataUrl.isEmpty) return;
      await widget.api.punchAttendance(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        selfieData: dataUrl,
      );
      await _refresh();
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _faceLabel(String value) => switch (value) {
    'matched' => 'WAJAH SEPADAN',
    'different' => 'WAJAH TIDAK SEPADAN',
    _ => 'SEMAKAN WAJAH DIPERLUKAN',
  };

  Color _faceColor(String value) => switch (value) {
    'matched' => const Color(0xFF00B894),
    'different' => const Color(0xFFFF7675),
    _ => const Color(0xFFFDCB6E),
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final nextType = status?.nextPunchType ?? 'IN';
    final nextLabel = nextType == 'IN' ? 'PUNCH MASUK' : 'PUNCH KELUAR';
    return Scaffold(
      appBar: AppBar(title: const Text('Kehadiran')),
      body: _loading && status == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF251A4F),
                          Color(0xFF171827),
                          Color(0xFF351315),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.fingerprint_rounded, size: 42),
                        const SizedBox(height: 14),
                        Text(
                          nextLabel,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(status?.department.name ?? widget.user.jabatan),
                        const SizedBox(height: 10),
                        Text(
                          status?.department.attendanceLatitude == null
                              ? 'Kawasan kehadiran belum ditetapkan oleh Admin.'
                              : 'Anda perlu berada dalam lingkungan ${status!.department.attendanceRadiusMeters}m dari kawasan yang ditetapkan dan ambil selfie.',
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_error!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 60,
                    child: FilledButton.icon(
                      onPressed: _punching ? null : _punch,
                      icon: Icon(
                        nextType == 'IN'
                            ? Icons.login_rounded
                            : Icons.logout_rounded,
                      ),
                      label: Text(_punching ? 'MENYIMPAN…' : nextLabel),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Lokasi semasa, ketepatan GPS dan selfie akan disimpan bersama rekod kehadiran. Jika selfie perlu diperiksa semula, Admin boleh membuat semakan daripada Sejarah Kehadiran.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Punch Hari Ini',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  if (status == null || status.records.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Belum ada punch kehadiran hari ini.'),
                      ),
                    )
                  else
                    ...status.records.reversed.map((record) {
                      final color = _faceColor(record.faceStatus);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              record.punchType == 'IN'
                                  ? Icons.login_rounded
                                  : Icons.logout_rounded,
                            ),
                          ),
                          title: Text(
                            '${record.punchType == 'IN' ? 'MASUK' : 'KELUAR'} • ${_time(record.punchedAt)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${record.distanceMeters.toStringAsFixed(0)}m dari pusat • GPS ±${record.accuracyMeters?.toStringAsFixed(0) ?? '-'}m',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              record.faceScore == null
                                  ? _faceLabel(record.faceStatus)
                                  : '${record.faceScore!.round()}%',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
