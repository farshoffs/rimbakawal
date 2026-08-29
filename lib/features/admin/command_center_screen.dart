import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import 'live_patrol_map_screen.dart';

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  CommandCenterData? _data;
  Timer? _timer;
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_refresh(silent: true)),
    );
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
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filteredPatrols {
    final rows = _data?.patrols ?? const [];
    if (_filter == 'alerts') {
      return rows
          .where((row) => row['status'] == 'late' || row['status'] == 'missed')
          .toList();
    }
    if (_filter == 'active') {
      return rows.where((row) => row['status'] == 'patrolling').toList();
    }
    if (_filter == 'complete') {
      return rows.where((row) => row['status'] == 'complete').toList();
    }
    return rows;
  }

  ImageProvider<Object>? _profileImage(Object? value) {
    final source = value as String?;
    if (source == null || source.isEmpty) return null;
    if (source.startsWith('data:image') && source.contains(',')) {
      try {
        return MemoryImage(base64Decode(source.split(',').last));
      } catch (_) {
        return null;
      }
    }
    final uri = Uri.tryParse(source);
    return uri != null && uri.hasScheme ? NetworkImage(source) : null;
  }

  Future<void> _updateIncident(int id, String status) async {
    try {
      await widget.api.updateIncidentStatus(id, status);
      await _refresh(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Insiden ditukar kepada ${status.toUpperCase()}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showIncidentImages(Map<String, dynamic> incident) async {
    final id = (incident['id'] as num?)?.toInt();
    if (id == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 700,
          height: 520,
          child: FutureBuilder<List<String>>(
            future: widget.api.getIncidentImages(id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(snapshot.error.toString()));
              }
              final images = snapshot.data ?? const [];
              if (images.isEmpty) {
                return const Center(child: Text('Tiada gambar untuk insiden ini.'));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Bukti Gambar',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      children: images.map((source) {
                        try {
                          final bytes = base64Decode(source.split(',').last);
                          return InteractiveViewer(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Image.memory(bytes, fit: BoxFit.contain),
                            ),
                          );
                        } catch (_) {
                          return const Center(child: Text('Gambar tidak dapat dibaca.'));
                        }
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'complete' => const Color(0xFF00B894),
        'patrolling' => const Color(0xFF6C5CE7),
        'late' => const Color(0xFFFDCB6E),
        'missed' => const Color(0xFFFF7675),
        'no_checkpoints' => const Color(0xFF636E72),
        _ => const Color(0xFF74B9FF),
      };

  String _statusLabel(String status) => switch (status) {
        'complete' => 'COMPLETE',
        'patrolling' => 'PATROLLING',
        'late' => 'LATE',
        'missed' => 'MISSED',
        'no_checkpoints' => 'NO CHECKPOINT',
        _ => 'WAITING',
      };

  String _time(Object? value) {
    final date = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}';
  }

  void _openLiveMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LivePatrolMapScreen(api: widget.api),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final summary = data?.summary ?? const <String, dynamic>{};
    final patrols = _filteredPatrols;
    final incidents = data?.incidents ?? const <Map<String, dynamic>>[];
    final sos = data?.sosEvents ?? const <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pemantauan Rondaan'),
        actions: [
          IconButton(
            tooltip: 'Live Map',
            onPressed: _openLiveMap,
            icon: const Icon(Icons.map_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _OperationsHero(
                      summary: summary,
                      generatedAt: data?.generatedAt,
                      onMap: _openLiveMap,
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
                    _SectionHeader(
                      title: 'Status Guard',
                      subtitle: '${data?.patrols.length ?? 0} pengguna dipantau',
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('Semua')),
                          ButtonSegment(
                            value: 'alerts',
                            icon: Icon(Icons.warning_amber_rounded),
                            label: Text('Alert'),
                          ),
                          ButtonSegment(
                            value: 'active',
                            icon: Icon(Icons.directions_walk_rounded),
                            label: Text('Ronda'),
                          ),
                          ButtonSegment(
                            value: 'complete',
                            icon: Icon(Icons.check_circle_outline_rounded),
                            label: Text('Selesai'),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (value) =>
                            setState(() => _filter = value.first),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (patrols.isEmpty)
                      const _EmptyState(
                        icon: Icons.shield_outlined,
                        text: 'Tiada guard dalam kategori ini.',
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 820;
                          if (!wide) {
                            return Column(
                              children: patrols
                                  .map(
                                    (row) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _PatrolCard(
                                        row: row,
                                        image: _profileImage(row['profilePicture']),
                                        color: _statusColor(
                                          row['status'] as String? ?? 'waiting',
                                        ),
                                        label: _statusLabel(
                                          row['status'] as String? ?? 'waiting',
                                        ),
                                        time: _time(row['lastScanAt']),
                                        onMap: _openLiveMap,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          }
                          return GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 2.25,
                            children: patrols
                                .map(
                                  (row) => _PatrolCard(
                                    row: row,
                                    image: _profileImage(row['profilePicture']),
                                    color: _statusColor(
                                      row['status'] as String? ?? 'waiting',
                                    ),
                                    label: _statusLabel(
                                      row['status'] as String? ?? 'waiting',
                                    ),
                                    time: _time(row['lastScanAt']),
                                    onMap: _openLiveMap,
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    const SizedBox(height: 22),
                    _SectionHeader(
                      title: 'Incident Queue',
                      subtitle: '${incidents.length} belum resolved',
                    ),
                    const SizedBox(height: 10),
                    if (incidents.isEmpty)
                      const _EmptyState(
                        icon: Icons.task_alt_rounded,
                        text: 'Tiada insiden terbuka.',
                      )
                    else
                      ...incidents.take(12).map(
                        (incident) => _IncidentCard(
                          incident: incident,
                          onAcknowledge: () => _updateIncident(
                            (incident['id'] as num).toInt(),
                            'acknowledged',
                          ),
                          onResolve: () => _updateIncident(
                            (incident['id'] as num).toInt(),
                            'resolved',
                          ),
                          onImages: (incident['image_count'] as num?)?.toInt() == 0
                              ? null
                              : () => _showIncidentImages(incident),
                        ),
                      ),
                    const SizedBox(height: 22),
                    _SectionHeader(
                      title: 'SOS • 24 Jam',
                      subtitle: '${sos.length} event',
                    ),
                    const SizedBox(height: 10),
                    if (sos.isEmpty)
                      const _EmptyState(
                        icon: Icons.sos_outlined,
                        text: 'Tiada SOS dalam 24 jam.',
                      )
                    else
                      ...sos.take(10).map(
                        (row) => Card(
                          color: const Color(0xFF2C1116),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0x33FF7675),
                              child: Icon(Icons.sos_rounded, color: Color(0xFFFF7675)),
                            ),
                            title: Text(
                              row['nama'] as String? ?? '-',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              '${row['jabatan'] ?? '-'} • ${_time(row['triggered_at'])}\n${row['note'] ?? 'Tiada catatan'}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OperationsHero extends StatelessWidget {
  const _OperationsHero({
    required this.summary,
    required this.generatedAt,
    required this.onMap,
  });
  final Map<String, dynamic> summary;
  final DateTime? generatedAt;
  final VoidCallback onMap;

  int _value(String key) => (summary[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final alerts = _value('alerts');
    final incidents = _value('openIncidents');
    final sos = _value('sos24h');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171F38), Color(0xFF211645), Color(0xFF351417)],
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
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.monitor_heart_rounded, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operations Command Center',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      'Auto-refresh 8 saat${generatedAt == null ? '' : ' • ${_clock(generatedAt!)}'}',
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Live Map',
                onPressed: onMap,
                icon: const Icon(Icons.map_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 18) / 3;
              return Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: _value('patrolUsers'),
                      label: 'GUARD',
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF74B9FF),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: _value('complete'),
                      label: 'COMPLETE',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF55E6C1),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: alerts,
                      label: 'ALERT',
                      icon: Icons.warning_amber_rounded,
                      color: alerts > 0
                          ? const Color(0xFFFF7675)
                          : const Color(0xFFB2BEC3),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: incidents,
                      label: 'INCIDENT',
                      icon: Icons.report_problem_rounded,
                      color: const Color(0xFFFDCB6E),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: _value('urgentIncidents'),
                      label: 'URGENT',
                      icon: Icons.priority_high_rounded,
                      color: const Color(0xFFFF9F43),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: sos,
                      label: 'SOS 24H',
                      icon: Icons.sos_rounded,
                      color: sos > 0
                          ? const Color(0xFFFF7675)
                          : const Color(0xFFB2BEC3),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final int value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

class _PatrolCard extends StatelessWidget {
  const _PatrolCard({
    required this.row,
    required this.image,
    required this.color,
    required this.label,
    required this.time,
    required this.onMap,
  });
  final Map<String, dynamic> row;
  final ImageProvider<Object>? image;
  final Color color;
  final String label;
  final String time;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final scanned = (row['scannedCount'] as num?)?.toInt() ?? 0;
    final expected = (row['expectedCount'] as num?)?.toInt() ?? 0;
    final progress = expected == 0 ? 0.0 : scanned / expected;
    final missed = (row['missedSessions'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: image,
              child: image == null ? const Icon(Icons.person_rounded) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row['nama'] as String? ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    row['jabatan'] as String? ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 7,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$scanned/$expected checkpoint • last scan $time${missed > 0 ? ' • $missed missed' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Live Map',
              onPressed: onMap,
              icon: const Icon(Icons.location_searching_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onImages,
  });
  final Map<String, dynamic> incident;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback? onImages;

  @override
  Widget build(BuildContext context) {
    final severity = incident['severity'] as String? ?? 'normal';
    final color = severity == 'urgent'
        ? const Color(0xFFFF7675)
        : severity == 'important'
            ? const Color(0xFFFDCB6E)
            : const Color(0xFF74B9FF);
    final status = incident['status'] as String? ?? 'open';
    final imageCount = (incident['image_count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.report_problem_rounded, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${incident['category'] ?? 'Incident'} • ${severity.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${incident['nama'] ?? '-'} • ${incident['jabatan'] ?? '-'} • ${incident['checkpoint_name'] ?? 'Tanpa checkpoint'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(incident['note'] as String? ?? '-'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (imageCount > 0)
                    OutlinedButton.icon(
                      onPressed: onImages,
                      icon: const Icon(Icons.photo_library_rounded),
                      label: Text('$imageCount Gambar'),
                    ),
                  if (status == 'open')
                    OutlinedButton.icon(
                      onPressed: onAcknowledge,
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('Acknowledge'),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Resolve'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
          child: Column(
            children: [
              Icon(icon, size: 38, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );
}
