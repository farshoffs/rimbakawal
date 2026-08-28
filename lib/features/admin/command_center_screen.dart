import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refresh(silent: true),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  ImageProvider<Object>? _imageProvider(Object? value) {
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

  Future<void> _openMap(num latitude, num longitude) async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Peta tidak dapat dibuka.')));
    }
  }

  Future<void> _showIncidentImages(int incidentId) async {
    try {
      final images = await widget.api.getIncidentImages(incidentId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gambar Laporan'),
          content: SizedBox(
            width: 620,
            child: images.isEmpty
                ? const Text('Tiada gambar dilampirkan.')
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: images.map((source) {
                        final provider = _imageProvider(source);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: provider == null
                              ? const SizedBox(
                                  width: 170,
                                  height: 170,
                                  child: Icon(Icons.broken_image_outlined),
                                )
                              : Image(
                                  image: provider,
                                  width: 170,
                                  height: 170,
                                  fit: BoxFit.cover,
                                ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
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
        return 'SELESAI';
      case 'patrolling':
        return 'MERONDA';
      case 'late':
        return 'LEWAT';
      case 'missed':
        return 'TERLEPAS';
      case 'no_checkpoints':
        return 'TIADA CHECKPOINT';
      default:
        return 'MENUNGGU';
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
        title: const Text('Pemantauan Rondaan'),
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
                          label: 'Peronda',
                          value: '${data.summary['patrolUsers'] ?? 0}',
                        ),
                        _StatCard(
                          icon: Icons.check_circle_rounded,
                          label: 'Selesai',
                          value: '${data.summary['complete'] ?? 0}',
                        ),
                        _StatCard(
                          icon: Icons.warning_amber_rounded,
                          label: 'Amaran',
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
                      'Lokasi & Status Rondaan Langsung',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (data.patrols.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('Tiada peronda aktif.'),
                        ),
                      )
                    else
                      ...data.patrols.map((row) {
                        final status = row['status'] as String? ?? 'waiting';
                        final scanned =
                            (row['scannedCount'] as num?)?.toInt() ?? 0;
                        final expected =
                            (row['expectedCount'] as num?)?.toInt() ?? 0;
                        final latitude = row['latitude'] as num?;
                        final longitude = row['longitude'] as num?;
                        final profile = _imageProvider(row['profilePicture']);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: _statusColor(status)
                                      .withValues(alpha: 0.15),
                                  backgroundImage: profile,
                                  child: profile == null
                                      ? Icon(
                                          Icons.person_pin_circle_rounded,
                                          color: _statusColor(status),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              row['nama'] as String? ?? '-',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              _statusLabel(status),
                                              style: TextStyle(
                                                color: _statusColor(status),
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${row['jabatan'] ?? '-'} • $scanned/$expected checkpoint',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Scan terakhir: ${_time(row['lastScanAt'] as String?)}',
                                      ),
                                      if (latitude != null &&
                                          longitude != null) ...[
                                        Text(
                                          'Lokasi dikemas kini: ${_time(row['locationAt'] as String?)}',
                                        ),
                                        const SizedBox(height: 6),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openMap(latitude, longitude),
                                          icon: const Icon(Icons.map_outlined),
                                          label: const Text(
                                            'Buka Lokasi Langsung',
                                          ),
                                        ),
                                      ] else if (status == 'patrolling')
                                        const Text(
                                          'Menunggu kebenaran/data lokasi…',
                                        ),
                                      if (((row['missedSessions'] as num?)
                                                  ?.toInt() ??
                                              0) >
                                          0)
                                        Text(
                                          'Sesi terlepas: ${row['missedSessions']}',
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 22),
                    Text(
                      'Laporan Insiden',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (data.incidents.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('Tiada insiden terbuka.'),
                        ),
                      )
                    else
                      ...data.incidents.map((row) {
                        final id = (row['id'] as num).toInt();
                        final severity = row['severity'] as String? ?? 'normal';
                        final status = row['status'] as String? ?? 'open';
                        final imageCount =
                            (row['image_count'] as num?)?.toInt() ?? 0;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      severity == 'urgent'
                                          ? Icons.priority_high_rounded
                                          : Icons.report_outlined,
                                      color: severity == 'urgent'
                                          ? Colors.red
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${row['category'] ?? 'Insiden'} • ${row['checkpoint_name'] ?? 'Tanpa checkpoint'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Chip(label: Text(status.toUpperCase())),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${row['nama'] ?? '-'} • ${row['jabatan'] ?? '-'}',
                                ),
                                const SizedBox(height: 6),
                                Text(row['note'] as String? ?? '-'),
                                if (imageCount > 0) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showIncidentImages(id),
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                      ),
                                      label: Text('Lihat Gambar ($imageCount)'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (status == 'open')
                                      TextButton(
                                        onPressed: () => _setIncidentStatus(
                                          id,
                                          'acknowledged',
                                        ),
                                        child: const Text('ACKNOWLEDGE'),
                                      ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: () =>
                                          _setIncidentStatus(id, 'resolved'),
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
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      ...data.sosEvents.map(
                        (row) => Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: ListTile(
                            leading: const Icon(Icons.sos_rounded),
                            title: Text(
                              '${row['nama'] ?? '-'} • ${row['jabatan'] ?? '-'}',
                            ),
                            subtitle: Text(
                              '${_time(row['triggered_at'] as String?)}\n${row['note'] ?? ''}',
                            ),
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
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });
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
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
