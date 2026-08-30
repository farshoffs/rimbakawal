import 'dart:convert';
import 'dart:typed_data';

import 'package:face_detection_tflite/face_detection_tflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({required this.api, super.key});
  final ApiService api;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late Future<AttendanceStatus> _future;
  bool _processing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getAttendanceStatus();
  }

  void _refresh() => setState(() => _future = widget.api.getAttendanceStatus());

  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Aktifkan GPS untuk merekod kehadiran.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Kebenaran lokasi diperlukan untuk merekod kehadiran.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Uint8List _dataUrlBytes(String value) =>
      base64Decode(value.substring(value.indexOf(',') + 1));

  Future<void> _punch(AttendanceStatus status) async {
    if (kIsWeb) {
      setState(() => _message = 'Pengesahan muka tersedia dalam aplikasi Android/iOS.');
      return;
    }
    if (!status.hasProfilePicture || status.profilePicture == null) {
      setState(() => _message = 'Sila tetapkan gambar profil terlebih dahulu.');
      return;
    }
    setState(() {
      _processing = true;
      _message = 'Mengesahkan lokasi…';
    });
    FaceDetector? detector;
    try {
      final position = await _position();
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 65,
        maxWidth: 720,
      );
      if (photo == null) return;
      final selfieBytes = await photo.readAsBytes();
      final profileBytes = _dataUrlBytes(status.profilePicture!);
      setState(() => _message = 'Mengesan dan memadankan wajah…');
      detector = await FaceDetector.create(model: FaceDetectionModel.frontCamera);
      final selfieFaces = await detector.detectFacesFromBytes(
        selfieBytes,
        mode: FaceDetectionMode.full,
      );
      final profileFaces = await detector.detectFacesFromBytes(
        profileBytes,
        mode: FaceDetectionMode.full,
      );
      final detected = selfieFaces.length == 1 && profileFaces.length == 1;
      var similarity = -1.0;
      if (detected) {
        final selfieEmbedding = await detector.getFaceEmbedding(
          selfieFaces.first,
          selfieBytes,
        );
        final profileEmbedding = await detector.getFaceEmbedding(
          profileFaces.first,
          profileBytes,
        );
        similarity = FaceDetector.compareFaces(profileEmbedding, selfieEmbedding);
      }
      final matched = detected && similarity >= status.faceThreshold;
      final mime = photo.path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      final record = await widget.api.punchAttendance(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        faceDetected: detected,
        faceMatched: matched,
        faceSimilarity: similarity,
        selfieImage: 'data:image/$mime;base64,${base64Encode(selfieBytes)}',
        devicePlatform: defaultTargetPlatform.name,
      );
      if (!mounted) return;
      setState(() => _message = record.eventType == 'in'
          ? 'Kehadiran masuk berjaya direkod.'
          : 'Kehadiran keluar berjaya direkod.');
      _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      detector?.dispose();
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kehadiran')),
      body: FutureBuilder<AttendanceStatus>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
            ));
          }
          final status = snapshot.requireData;
          final isIn = status.nextEventType == 'in';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(isIn ? Icons.login_rounded : Icons.logout_rounded, size: 64),
                    const SizedBox(height: 10),
                    Text(isIn ? 'Punch Masuk' : 'Punch Keluar',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            )),
                    const SizedBox(height: 8),
                    Text('${status.department['name']} • Radius ${status.department['radiusMeters']}m'),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _processing ? null : () => _punch(status),
                      icon: const Icon(Icons.face_retouching_natural_rounded),
                      label: Text(_processing ? 'Memproses…' : 'Tangkap Muka & Rekod'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Text(_message!, textAlign: TextAlign.center),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Text('Rekod hari ini', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 8),
              if (status.records.isEmpty)
                const Card(child: ListTile(title: Text('Belum ada rekod kehadiran.')))
              else
                ...status.records.reversed.map((record) => Card(
                      child: ListTile(
                        leading: Icon(record.status == 'accepted'
                            ? Icons.verified_rounded
                            : Icons.cancel_rounded),
                        title: Text(record.eventType == 'in' ? 'Masuk' : 'Keluar'),
                        subtitle: Text(record.status == 'accepted'
                            ? 'Jarak ${record.distanceMeters.toStringAsFixed(0)}m • Padanan muka ${((record.faceSimilarity ?? 0) * 100).toStringAsFixed(0)}%'
                            : record.rejectionReason ?? 'Tidak diterima'),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}
