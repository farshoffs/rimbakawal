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
    _subscription = NotificationService.instance.foregroundAlerts.listen(_onAlert);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _onAlert(PushAlert alert) async {
    if (!mounted || _showing) return;
    // Dedicated existing UI already handles these two with louder/full-screen UX.
    if (alert.kind == 'sos' || alert.kind == 'session_start') return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(_icon(alert.kind), size: 48, color: _accent(alert.kind)),
          title: Text(alert.title, textAlign: TextAlign.center),
          content: Text(alert.body, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('SAYA FAHAM'),
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
        _ => Icons.notifications_active_rounded,
      };

  Color _accent(String kind) => switch (kind) {
        'incident_urgent' => const Color(0xFFFF5D66),
        'welfare_attention' => const Color(0xFFFFB142),
        'sos_resolved' => const Color(0xFF55E6C1),
        _ => const Color(0xFFA29BFE),
      };

  @override
  Widget build(BuildContext context) => widget.child;
}
