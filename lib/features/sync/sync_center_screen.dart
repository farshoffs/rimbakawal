import 'package:flutter/material.dart';

import '../../core/api/app_user.dart';
import '../../core/offline/offline_models.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/offline_sync_service.dart';

class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  final OfflineStore _store = OfflineStore.instance;
  final OfflineSyncService _sync = OfflineSyncService.instance;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _sync.addListener(_changed);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = _store.eventsForUser(widget.user.id, limit: 300);
    final pending = all.where((event) => event.isPending).length;
    final failed = all.where((event) => event.isFailed).length;
    final synced = all.where((event) => event.isSynced).length;
    final events = all.where((event) {
      if (_filter == 'pending') return event.isPending;
      if (_filter == 'failed') return event.isFailed;
      if (_filter == 'synced') return event.isSynced;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Sync Center')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _sync.syncNow,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF17223D), Color(0xFF211646), Color(0xFF171820)],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            _sync.isSyncing
                                ? Icons.sync_rounded
                                : Icons.offline_bolt_rounded,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _sync.isSyncing
                                    ? 'Sedang sync…'
                                    : pending == 0
                                        ? 'Semua data selamat'
                                        : '$pending event menunggu cloud',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Rondaan kekal berfungsi walaupun internet terputus.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.68),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(child: _Metric(value: pending, label: 'Pending')),
                        const SizedBox(width: 8),
                        Expanded(child: _Metric(value: synced, label: 'Synced')),
                        const SizedBox(width: 8),
                        Expanded(child: _Metric(value: failed, label: 'Failed')),
                      ],
                    ),
                    if (_sync.lastSyncAt != null) ...[
                      const SizedBox(height: 12),
                      Text('Sync terakhir: ${_dateTime(_sync.lastSyncAt!)}'),
                    ],
                    if (_sync.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _sync.lastError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _sync.isSyncing ? null : _sync.syncNow,
                            icon: const Icon(Icons.sync_rounded),
                            label: const Text('SYNC SEKARANG'),
                          ),
                        ),
                        if (failed > 0) ...[
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Retry failed',
                            onPressed: _sync.retryFailed,
                            icon: const Icon(Icons.restart_alt_rounded),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Semua')),
                    ButtonSegment(value: 'pending', label: Text('Pending')),
                    ButtonSegment(value: 'failed', label: Text('Failed')),
                    ButtonSegment(value: 'synced', label: Text('Synced')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
              const SizedBox(height: 14),
              if (events.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('Tiada event untuk paparan ini.')),
                  ),
                )
              else
                ...events.map((event) => _EventCard(event: event)),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final OfflineEvent event;

  @override
  Widget build(BuildContext context) {
    final color = event.isSynced
        ? const Color(0xFF55E6C1)
        : event.isFailed
            ? const Color(0xFFFF7675)
            : const Color(0xFFFFD166);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(_icon(event.type), color: color),
          ),
          title: Text(
            _label(event.type),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${_time(event.occurredAt)} • ${event.isSynced ? 'Synced' : event.isFailed ? event.lastError ?? 'Failed' : 'Pending'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            event.isSynced
                ? Icons.cloud_done_rounded
                : event.isFailed
                    ? Icons.error_outline_rounded
                    : Icons.cloud_upload_outlined,
            color: color,
          ),
        ),
      ),
    );
  }

  static IconData _icon(String type) => switch (type) {
        'scan' => Icons.nfc_rounded,
        'incident' => Icons.report_problem_rounded,
        'sos' => Icons.sos_rounded,
        'patrol_start' => Icons.play_circle_rounded,
        'patrol_end' => Icons.stop_circle_rounded,
        'welfare_check' => Icons.health_and_safety_rounded,
        _ => Icons.bolt_rounded,
      };

  static String _label(String type) => switch (type) {
        'scan' => 'Checkpoint Scan',
        'incident' => 'Incident Report',
        'sos' => 'SOS',
        'patrol_start' => 'Mula Rondaan',
        'patrol_end' => 'Tamat Rondaan',
        'welfare_check' => 'Welfare Check',
        _ => type,
      };

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}
