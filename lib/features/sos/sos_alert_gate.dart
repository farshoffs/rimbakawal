import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/app_user.dart';
import 'sos_alert_api.dart';

class SosAlertGate extends StatefulWidget {
  const SosAlertGate({
    required this.user,
    required this.child,
    super.key,
  });

  final AppUser user;
  final Widget child;

  @override
  State<SosAlertGate> createState() => _SosAlertGateState();
}

class _SosAlertGateState extends State<SosAlertGate>
    with WidgetsBindingObserver {
  final SosAlertApi _api = SosAlertApi.instance;
  final AudioPlayer _alarmPlayer = AudioPlayer();
  Timer? _timer;
  bool _polling = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_poll()),
    );
    Future<void>.delayed(const Duration(milliseconds: 900), _poll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _alarmPlayer.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted || _polling || _showing) return;
    _polling = true;
    try {
      final alerts = await _api.fetchAlerts();
      if (!mounted || alerts.isEmpty) return;
      await _showAlert(alerts.first);
    } catch (_) {
      // SOS polling is best-effort. Offline users receive the alert after reconnecting.
    } finally {
      _polling = false;
    }
  }

  Future<void> _playAlarm() async {
    try {
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.setVolume(1);
      await _alarmPlayer.play(AssetSource('audio/patrol_alarm.wav'));
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _showAlert(Map<String, dynamic> event) async {
    if (!mounted || _showing) return;
    final id = (event['id'] as num?)?.toInt();
    if (id == null) return;

    _showing = true;
    await _playAlarm();
    if (!mounted) {
      await _alarmPlayer.stop();
      _showing = false;
      return;
    }

    bool resolved = false;
    try {
      resolved = await showGeneralDialog<bool>(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.black.withValues(alpha: 0.96),
            transitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (dialogContext, _, _) => Scaffold(
              backgroundColor: const Color(0xFF180305),
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF561019),
                              Color(0xFF25070B),
                              Color(0xFF17101F),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFF7675).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.sos_rounded,
                              size: 108,
                              color: Color(0xFFFF7675),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ALERT SOS JABATAN',
                              textAlign: TextAlign.center,
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .headlineLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              event['jabatan'] as String? ?? widget.user.jabatan,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFB8B8),
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _InfoRow(
                              label: 'Pengguna',
                              value: event['nama'] as String? ?? '-',
                            ),
                            _InfoRow(
                              label: 'Jawatan',
                              value: event['jawatan'] as String? ?? '-',
                            ),
                            _InfoRow(
                              label: 'Masa',
                              value: _dateTime(event['triggered_at']),
                            ),
                            _InfoRow(
                              label: 'Catatan',
                              value: (event['note'] as String?)?.trim().isNotEmpty == true
                                  ? event['note'] as String
                                  : 'Tiada catatan',
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'SOS ini masih ACTIVE sehingga Supervisor atau Management menandakan ia selesai.',
                              textAlign: TextAlign.center,
                              style: TextStyle(height: 1.45),
                            ),
                            const SizedBox(height: 22),
                            if (widget.user.canMonitor) ...[
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF00B894),
                                ),
                                onPressed: () => unawaited(
                                  _resolveFromAlert(dialogContext, id),
                                ),
                                icon: const Icon(Icons.task_alt_rounded),
                                label: const Text('TANDAKAN SELESAI'),
                              ),
                              const SizedBox(height: 8),
                            ],
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(dialogContext).pop(false),
                              icon: const Icon(Icons.visibility_rounded),
                              label: const Text('TUTUP ALERT'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ) ??
          false;

      if (!resolved) {
        try {
          await _api.acknowledge(id);
        } catch (_) {}
      }
    } finally {
      await _alarmPlayer.stop();
      _showing = false;
    }

    if (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      unawaited(_poll());
    }
  }

  Future<void> _resolveFromAlert(BuildContext dialogContext, int sosId) async {
    final note = await _askResolutionNote();
    if (note == null || !dialogContext.mounted) return;
    try {
      await _api.resolve(sosId, note);
      if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
    } catch (error) {
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<String?> _askResolutionNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selesaikan SOS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Catatan penyelesaian diperlukan untuk rekod audit.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Catatan penyelesaian',
                hintText: 'Contoh: Guard telah ditemui dan keadaan disahkan selamat.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final note = controller.text.trim();
              if (note.isEmpty) return;
              Navigator.pop(context, note);
            },
            child: const Text('Sahkan Selesai'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  String _dateTime(Object? value) {
    final date = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFFFB8B8),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
