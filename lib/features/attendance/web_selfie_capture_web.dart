// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Future<String?> captureWebSelfie(BuildContext context) async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) {
    throw StateError('Pelayar ini tidak menyediakan akses webcam.');
  }

  final stream = await mediaDevices.getUserMedia({
    'video': {
      'facingMode': {'ideal': 'user'},
      'width': {'ideal': 720},
      'height': {'ideal': 720},
    },
    'audio': false,
  });
  final video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..srcObject = stream
    ..setAttribute('playsinline', 'true')
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'cover';

  try {
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 10));
    await video.play();
    final viewType =
        'rimbakawal-selfie-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) => video);

    if (!context.mounted) return null;
    final takePhoto = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ambil Selfie'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pastikan wajah jelas dan berada di tengah kamera.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: HtmlElementView(viewType: viewType),
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('AMBIL GAMBAR'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (takePhoto != true) return null;

    final width = video.videoWidth > 0 ? video.videoWidth : 720;
    final height = video.videoHeight > 0 ? video.videoHeight : 720;
    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImageScaled(video, 0, 0, width, height);
    return canvas.toDataUrl('image/jpeg', 0.72);
  } on TimeoutException {
    throw StateError(
      'Webcam mengambil masa terlalu lama untuk bermula. Cuba semula.',
    );
  } finally {
    for (final track in stream.getTracks()) {
      track.stop();
    }
    video.srcObject = null;
  }
}
