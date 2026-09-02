import 'dart:async';

import 'package:flutter/material.dart';

import 'notification_service.dart';

class NotificationAlertGate extends StatefulWidget {
  const NotificationAlertGate({required this.child, super.key});
  final Widget child;

  @override
  State<NotificationAlertGate> createState() => _NotificationAlertGateState();
}

class _NotificationAlertGateState extends State<NotificationAlertGate> {
  StreamSubscription<PushAlert>? _subscription;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService.instance.foregroundAlerts.listen(
      _onAlert,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _onAlert(PushAlert alert) async {
    if (!mounted || _showing) return;
    // SOS has a dedicated full-screen alarm/polling experience.
    if (alert.kind == 'sos') return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF222636),
          icon: Icon(_icon(alert.kind), size: 48, color: _accent(alert.kind)),
          title: Text(
            alert.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            alert.body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('TUTUP'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                NotificationService.instance.openAlert(alert);
              },
              icon: Icon(_openIcon(alert.kind)),
              label: Text(_openLabel(alert.kind)),
            ),
          ],
        ),
      );
    } finally {
      _showing = false;
    }
  }

  IconData _icon(String kind) => switch (kind) {
    'incident_urgent' => Icons.warning_rounded,
    'incident' => Icons.report_problem_rounded,
    'welfare_attention' => Icons.health_and_safety_rounded,
    'sos_resolved' => Icons.task_alt_rounded,
    'session_start' => Icons.directions_walk_rounded,
    'patrol_not_started' => Icons.timer_off_rounded,
    'session_ending' => Icons.timer_rounded,
    'session_missed' || 'session_incomplete' => Icons.event_busy_rounded,
    'checkpoint_scanned' => Icons.nfc_rounded,
    'patrol_completed' => Icons.verified_rounded,
    'patrol_ended' => Icons.flag_rounded,
    'attendance_punch' => Icons.fingerprint_rounded,
    'attendance_review' => Icons.face_retouching_natural_rounded,
    _ => Icons.notifications_active_rounded,
  };

  Color _accent(String kind) => switch (kind) {
    'incident_urgent' || 'session_missed' => const Color(0xFFFF5D66),
    'welfare_attention' ||
    'session_ending' ||
    'attendance_review' => const Color(0xFFFFB142),
    'sos_resolved' ||
    'patrol_completed' ||
    'attendance_punch' => const Color(0xFF55E6C1),
    _ => const Color(0xFFA29BFE),
  };

  IconData _openIcon(String kind) => switch (kind) {
    'session_start' ||
    'patrol_not_started' ||
    'session_ending' => Icons.directions_walk_rounded,
    'attendance_punch' || 'attendance_review' => Icons.fingerprint_rounded,
    _ => Icons.open_in_new_rounded,
  };

  String _openLabel(String kind) => switch (kind) {
    'session_start' ||
    'patrol_not_started' ||
    'session_ending' => 'MULA RONDAAN',
    _ => 'BUKA',
  };

  @override
  Widget build(BuildContext context) => widget.child;
}
