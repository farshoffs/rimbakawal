import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';

class ClockingHistoryScreen extends StatefulWidget {
  const ClockingHistoryScreen({
    required this.api,
    required this.user,
    super.key,
  });

  final ApiService api;
  final AppUser user;

  @override
  State<ClockingHistoryScreen> createState() => _ClockingHistoryScreenState();
}

class _ClockingHistoryScreenState extends State<ClockingHistoryScreen> {
  DateTime _selectedDate = DateTime.now();
  int? _selectedDepartmentId;
  List<DepartmentRecord> _departments = const [];
  late Future<HistoryDay> _future;

  @override
  void initState() {
    super.initState();
    _selectedDepartmentId = widget.user.departmentId;
    _future = widget.user.isManagement
        ? _loadManagementInitial()
        : widget.api.getHistory(_selectedDate);
  }

  Future<HistoryDay> _loadManagementInitial() async {
    final departments = await widget.api.getAdminDepartments();
    final selected =
        _selectedDepartmentId ??
        (departments.isEmpty ? null : departments.first.id);
    if (mounted) {
      setState(() {
        _departments = departments;
        _selectedDepartmentId = selected;
      });
    }
    if (selected == null) {
      throw const ApiException('Tiada Jabatan tersedia untuk dipaparkan.');
    }
    return widget.api.getHistory(_selectedDate, departmentId: selected);
  }

  void _load(DateTime date, {int? departmentId}) {
    final normalized = DateTime(date.year, date.month, date.day);
    final selected = departmentId ?? _selectedDepartmentId;
    setState(() {
      _selectedDate = normalized;
      if (departmentId != null) _selectedDepartmentId = departmentId;
      _future = widget.api.getHistory(
        normalized,
        departmentId: widget.user.isManagement ? selected : null,
      );
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Pilih tarikh rekod',
    );
    if (picked != null) _load(picked);
  }

  String _formatDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sejarah Rondaan'),
        actions: [
          IconButton(
            tooltip: 'Muat semula',
            onPressed: () => _load(_selectedDate),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.user.isManagement) ...[
                        DropdownButtonFormField<int>(
                          initialValue: _selectedDepartmentId,
                          decoration: const InputDecoration(
                            labelText: 'Jabatan',
                            prefixIcon: Icon(Icons.apartment_rounded),
                          ),
                          items: _departments
                              .map(
                                (department) => DropdownMenuItem<int>(
                                  value: department.id,
                                  child: Text(
                                    department.active
                                        ? department.name
                                        : '${department.name} (Tidak aktif)',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _load(_selectedDate, departmentId: value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Tarikh: ${_formatDate(_selectedDate)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Hari ini'),
                            selected: _sameDay(_selectedDate, today),
                            onSelected: (_) => _load(today),
                          ),
                          ChoiceChip(
                            label: const Text('Semalam'),
                            selected: _sameDay(_selectedDate, yesterday),
                            onSelected: (_) => _load(yesterday),
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.calendar_month_rounded,
                              size: 18,
                            ),
                            label: const Text('Pilih tarikh'),
                            onPressed: _pickDate,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<HistoryDay>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final history = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        '${history.department} • Sesi rondaan setiap ${history.sessionIntervalMinutes} minit',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.route_rounded),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sesi Rondaan',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text('${history.patrolRuns.length} sesi'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (history.patrolRuns.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              'Tiada sesi yang dimulakan melalui Mula Rondaan untuk tarikh ini.',
                            ),
                          ),
                        )
                      else
                        ...history.patrolRuns.map(
                          (run) =>
                              _PatrolRunCard(run: run, formatTime: _formatTime),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatrolRunCard extends StatelessWidget {
  const _PatrolRunCard({required this.run, required this.formatTime});

  final HistoryPatrolRun run;
  final String Function(DateTime) formatTime;

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) {
        try {
          return MemoryImage(base64Decode(picture.substring(comma + 1)));
        } catch (_) {
          return null;
        }
      }
    }
    return NetworkImage(picture);
  }

  String _duration() {
    final seconds = run.durationSeconds;
    if (seconds == null) return 'Belum tamat';
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return '${duration.inHours}j ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes} minit';
    return '${duration.inSeconds} saat';
  }

  void _showTrail(BuildContext context) {
    final points = run.trail
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (points.isEmpty) return;
    final latitude =
        points.map((point) => point.latitude).reduce((a, b) => a + b) /
        points.length;
    final longitude =
        points.map((point) => point.longitude).reduce((a, b) => a + b) /
        points.length;
    final center = LatLng(latitude, longitude);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text(
                  '${run.userName} • Sesi Rondaan ${run.sessionIndex + 1}\n${formatTime(run.startedAt)} - ${run.endedAt == null ? 'Belum tamat' : formatTime(run.endedAt!)} • ${run.trailPointCount} titik GPS',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: points.length == 1 ? 17 : 16,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'dev.rimbakawal.app',
                    ),
                    if (points.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: points,
                            strokeWidth: 5,
                            color: const Color(0xFFFFD54F),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: points.first,
                          width: 52,
                          height: 52,
                          child: const CircleAvatar(
                            backgroundColor: Color(0xFF00B894),
                            child: Icon(Icons.play_arrow_rounded),
                          ),
                        ),
                        if (points.length > 1)
                          Marker(
                            point: points.last,
                            width: 52,
                            height: 52,
                            child: const CircleAvatar(
                              backgroundColor: Color(0xFFC0392B),
                              child: Icon(Icons.stop_rounded),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  'Peta © penyumbang OpenStreetMap • hijau = mula • merah = lokasi akhir trail',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageProvider(run.profilePicture);
    final scheme = Theme.of(context).colorScheme;
    final statusColor = run.isComplete
        ? Colors.greenAccent
        : run.isInProgress
        ? scheme.secondary
        : scheme.error;
    final statusLabel = switch (run.status) {
      'complete' => 'LENGKAP',
      'in_progress' => 'SEDANG BERJALAN',
      'no_checkpoints' => 'TIADA CHECKPOINT',
      _ => 'TIDAK LENGKAP',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: image,
                  child: image == null
                      ? Text(run.userName.isEmpty ? '?' : run.userName[0])
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        run.userName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('Sesi Rondaan ${run.sessionIndex + 1}'),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HistoryChip(
                  icon: Icons.play_circle_outline_rounded,
                  text: 'Mula ${formatTime(run.startedAt)}',
                ),
                _HistoryChip(
                  icon: Icons.stop_circle_outlined,
                  text: run.endedAt == null
                      ? 'Tamat belum direkod'
                      : 'Tamat ${formatTime(run.endedAt!)}',
                ),
                _HistoryChip(icon: Icons.timer_outlined, text: _duration()),
                _HistoryChip(
                  icon: Icons.route_rounded,
                  text: '${run.trailPointCount} titik GPS',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${run.scannedCount}/${run.expectedCount} checkpoint direkodkan dalam sesi ini',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (run.missingCheckpointNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Belum diimbas: ${run.missingCheckpointNames.join(', ')}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            if (run.scans.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...run.scans.map(
                (scan) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nfc_rounded),
                  title: Text(
                    scan.checkpointName ?? 'Checkpoint tidak dikenal pasti',
                  ),
                  subtitle: Text(
                    '${scan.nfcUid} • ${formatTime(scan.scannedAt)}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: run.trail.isEmpty ? null : () => _showTrail(context),
              icon: const Icon(Icons.map_rounded),
              label: const Text('LIHAT TRAIL RONDAAN'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.formatTime});

  final HistorySession session;
  final String Function(DateTime) formatTime;

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) {
        try {
          return MemoryImage(base64Decode(picture.substring(comma + 1)));
        } catch (_) {
          return null;
        }
      }
    }
    return NetworkImage(picture);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = session.isMissed
        ? scheme.error
        : session.isComplete
        ? Colors.greenAccent
        : scheme.secondary;
    final statusLabel = switch (session.status) {
      'complete' => 'LENGKAP',
      'missed' => 'CHECKPOINT TERLEPAS',
      'in_progress' => 'SESI SEMASA',
      'no_checkpoints' => 'TIADA CHECKPOINT',
      _ => session.status.toUpperCase(),
    };
    final image = _imageProvider(session.profilePicture);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: session.isMissed
              ? scheme.error.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.08),
          width: session.isMissed ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: image,
                  child: image == null
                      ? Text(
                          session.userName.isEmpty ? '?' : session.userName[0],
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.userName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sesi Rondaan ${session.index + 1} • ${formatTime(session.startAt)} - ${formatTime(session.endAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${session.scannedCount}/${session.expectedCount} checkpoint direkodkan',
            ),
            if (session.missingCheckpointNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (session.isMissed ? scheme.error : scheme.secondary)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${session.isMissed ? 'TERLEPAS' : 'Belum diimbas'}: ${session.missingCheckpointNames.join(', ')}',
                  style: TextStyle(
                    color: session.isMissed ? scheme.error : null,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            if (session.scans.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...session.scans.map(
                (scan) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nfc_rounded),
                  title: Text(
                    scan.checkpointName ?? 'Checkpoint tidak dikenal pasti',
                  ),
                  subtitle: Text(
                    '${scan.userName ?? session.userName} • ${scan.nfcUid} • ${formatTime(scan.scannedAt)}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
