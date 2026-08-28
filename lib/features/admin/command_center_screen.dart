import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  CommandCenterData? _data;
  String? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await widget.api.getCommandCenter();
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _setIncidentStatus(int id, String status) async {
    try {
      await widget.api.updateIncidentStatus(id, status);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'complete':
        return Colors.green;
      case 'patrolling':
        return Colors.blue;
      case 'late':
        return Colors.orange;
      case 'missed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'complete':
        return 'COMPLETE';
      case 'patrolling':
        return 'PATROLLING';
      case 'late':
        return 'LATE';
      case 'missed':
        return 'MISSED';
      case 'no_checkpoints':
        return 'NO CHECKPOINT';
      default:
        return 'WAITING';
    }
  }

  String _time(String? value) {
    if (value == null) return 'Belum ada scan';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Command Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (data != null) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StatCard(
                          icon: Icons.shield_rounded,
                          label: 'Patrol',
                          value: '${data.summary['patrolUsers'] ?? 0}',
                        ),
                        _StatCard(
                          icon: Icons.check_circle_rounded,
                          label: 'Complete',
                          value: '${data.summary['complete'] ?? 0}',
                        ),
                        _StatCard(
                          icon: Icons.warning_amber_rounded,
                          label: 'Alert',
                          value: '${data.summary['alerts'] ?? 0}',
                        ),
                        _StatCard(
                          icon: Icons.report_problem_rounded,
                          label: 'Insiden',
                          value: '${data.summary['openIncidents'] ?? 0}',
                        ),
                        _StatCard(
                          icon: Icons.sos_rounded,
                          label: 'SOS 24j',
                          value: '${data.summary['sos24h'] ?? 0}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Live Patrol Status',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (data.patrols.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Tiada Patrol aktif.')))
                    else
                      ...data.patrols.map((row) {
                        final status = row['status'] as String? ?? 'waiting';
                        final scanned = (row['scannedCount'] as num?)?.toInt() ?? 0;
                        final expected = (row['expectedCount'] as num?)?.toInt() ?? 0;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                              child: Icon(Icons.person_pin_circle_rounded, color: _statusColor(status)),
                            ),
                            title: Text(
                              row['nama'] as String? ?? '-',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${row['jabatan'] ?? '-'}\n$scanned/$expected checkpoint • Last: ${_time(row['lastScanAt'] as String?)}'
                              '${((row['missedSessions'] as num?)?.toInt() ?? 0) > 0 ? '\nMissed session: ${row['missedSessions']}' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: Chip(
                              label: Text(
                                _statusLabel(status),
                                style: TextStyle(
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 22),
                    Text(
                      'Incident / Job Order',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (data.incidents.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Tiada insiden terbuka.')))
                    else
                      ...data.incidents.map((row) {
                        final id = (row['id'] as num).toInt();
                        final severity = row['severity'] as String? ?? 'normal';
                        final status = row['status'] as String? ?? 'open';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      severity == 'urgent' ? Icons.priority_high_rounded : Icons.report_outlined,
                                      color: severity == 'urgent' ? Colors.red : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${row['category'] ?? 'Insiden'} • ${row['checkpoint_name'] ?? 'Tanpa checkpoint'}',
                                        style: const TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    Chip(label: Text(status.toUpperCase())),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('${row['nama'] ?? '-'} • ${row['jabatan'] ?? '-'}'),
                                const SizedBox(height: 6),
                                Text(row['note'] as String? ?? '-'),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (status == 'open')
                                      TextButton(
                                        onPressed: () => _setIncidentStatus(id, 'acknowledged'),
                                        child: const Text('ACKNOWLEDGE'),
                                      ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: () => _setIncidentStatus(id, 'resolved'),
                                      child: const Text('RESOLVE'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    if (data.sosEvents.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text(
                        'SOS Terkini',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      ...data.sosEvents.map(
                        (row) => Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: ListTile(
                            leading: const Icon(Icons.sos_rounded),
                            title: Text('${row['nama'] ?? '-'} • ${row['jabatan'] ?? '-'}'),
                            subtitle: Text('${_time(row['triggered_at'] as String?)}\n${row['note'] ?? ''}'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Auto-refresh setiap 10 saat • ${_time(data.generatedAt.toIso8601String())}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 10),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
