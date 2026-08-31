import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../history/clocking_history_screen.dart';
import 'attendance_history_screen.dart';
import 'live_patrol_map_screen.dart';
import 'sos_management_screen.dart';

enum _PeriodMode { day, week, month }

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
  _PeriodMode _mode = _PeriodMode.day;
  DateTime _anchor = DateTime.now();
  late DateTime _from;
  late DateTime _to;
  final _incidentsKey = GlobalKey();
  final _attendanceKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _recalculateRange();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_rangeContainsToday) unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool get _rangeContainsToday {
    final today = _dateOnly(DateTime.now());
    return !today.isBefore(_from) && !today.isAfter(_to);
  }

  void _recalculateRange() {
    final anchor = _dateOnly(_anchor);
    final today = _dateOnly(DateTime.now());
    switch (_mode) {
      case _PeriodMode.day:
        _from = anchor;
        _to = anchor;
      case _PeriodMode.week:
        _from = anchor.subtract(Duration(days: anchor.weekday - 1));
        final end = _from.add(const Duration(days: 6));
        _to = end.isAfter(today) ? today : end;
      case _PeriodMode.month:
        _from = DateTime(anchor.year, anchor.month, 1);
        final end = DateTime(anchor.year, anchor.month + 1, 0);
        _to = end.isAfter(today) ? today : end;
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await widget.api.getCommandCenter(
        from: _from,
        to: _to,
        mode: _mode.name,
      );
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

  Future<void> _changeMode(_PeriodMode mode) async {
    setState(() {
      _mode = mode;
      _recalculateRange();
    });
    await _refresh();
  }

  Future<void> _pickAnchor() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor.isAfter(DateTime.now()) ? DateTime.now() : _anchor,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: switch (_mode) {
        _PeriodMode.day => 'Pilih hari pemantauan',
        _PeriodMode.week => 'Pilih mana-mana hari dalam minggu',
        _PeriodMode.month => 'Pilih mana-mana hari dalam bulan',
      },
    );
    if (picked == null) return;
    setState(() {
      _anchor = picked;
      _recalculateRange();
    });
    await _refresh();
  }

  String _date(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _periodLabel() =>
      _from == _to ? _date(_from) : '${_date(_from)} – ${_date(_to)}';

  DateTime? _dateFromKey(Object? value) {
    final parts = (value as String? ?? '').split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  String _time(Object? value) {
    final parsed = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (parsed == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  String _dateTime(Object? value) {
    final parsed = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (parsed == null) return '-';
    return '${_date(parsed)} ${_time(value)}';
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

  void _openLiveMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LivePatrolMapScreen(api: widget.api),
      ),
    );
  }

  Future<void> _openHistory({
    required DateTime date,
    int? departmentId,
    String filter = 'all',
  }) async {
    final user = await widget.api.getSession();
    if (!mounted) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi telah tamat. Sila log masuk semula.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClockingHistoryScreen(
          api: widget.api,
          user: user,
          initialDate: date,
          initialDepartmentId: departmentId,
          initialFilter: filter,
        ),
      ),
    );
  }

  void _openAttendance() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AttendanceHistoryScreen(api: widget.api, initialDate: _to),
      ),
    );
  }

  void _openSos() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SosManagementScreen()),
    );
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.08,
    );
  }

  Future<void> _showGuardActivity() async {
    final rows = _data?.guardActivity ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      _message('Tiada aktiviti rondaan dalam tempoh ini.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _DetailSheet(
        title: 'Aktiviti Peronda • ${_periodLabel()}',
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final date =
                DateTime.tryParse(
                  row['lastScanAt'] as String? ?? '',
                )?.toLocal() ??
                _to;
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: _profileImage(row['profilePicture']),
                child: _profileImage(row['profilePicture']) == null
                    ? const Icon(Icons.person_rounded)
                    : null,
              ),
              title: Text(
                row['nama'] as String? ?? 'Pengawal',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${row['jabatan'] ?? '-'} • ${row['scanCount'] ?? 0} scan • ${row['sessionCount'] ?? 0} sesi • ${row['activeDays'] ?? 0} hari\nTerakhir: ${_dateTime(row['lastScanAt'])}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(
                  _openHistory(
                    date: DateTime(date.year, date.month, date.day),
                    departmentId: (row['departmentId'] as num?)?.toInt(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCoverageDays({
    required String title,
    String historyFilter = 'all',
    bool onlyComplete = false,
  }) async {
    final source = _data?.coverageDays ?? const <Map<String, dynamic>>[];
    final rows =
        source
            .where(
              (row) =>
                  !onlyComplete ||
                  ((row['completeSessions'] as num?)?.toInt() ?? 0) > 0,
            )
            .toList()
          ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    if (rows.isEmpty) {
      _message('Tiada rekod yang sepadan dalam tempoh ini.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _DetailSheet(
        title: '$title • ${_periodLabel()}',
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final date = _dateFromKey(row['date']) ?? _to;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.route_rounded)),
              title: Text(
                '${row['department'] ?? 'Jabatan'} • ${_date(date)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${row['completeSessions'] ?? 0} lengkap • ${row['missedSessions'] ?? 0} terlepas • ${row['scannedCheckpoints'] ?? 0}/${row['dueCheckpoints'] ?? 0} checkpoint',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(
                  _openHistory(
                    date: date,
                    departmentId: (row['departmentId'] as num?)?.toInt(),
                    filter: historyFilter,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showMissedDetails() async {
    final rows = [...?_data?.missedDetails]
      ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    if (rows.isEmpty) {
      _message('Tiada checkpoint atau sesi terlepas dalam tempoh ini.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _DetailSheet(
        title: 'Checkpoint / Sesi Terlepas • ${_periodLabel()}',
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final date = _dateFromKey(row['date']) ?? _to;
            final missing =
                (row['missingCheckpoints'] as List<dynamic>? ?? const [])
                    .map(
                      (item) => Map<String, dynamic>.from(item as Map)['name'],
                    )
                    .join(', ');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.location_off_rounded),
                ),
                title: Text(
                  '${row['department'] ?? 'Jabatan'} • ${_date(date)} • Sesi ${row['sessionIndex'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  'Terlepas: ${missing.isEmpty ? '-' : missing}\nDirekod ${row['scannedCount'] ?? 0}/${row['expectedCount'] ?? 0} checkpoint',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    _openHistory(
                      date: date,
                      departmentId: (row['departmentId'] as num?)?.toInt(),
                      filter: 'missed',
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _updateIncident(int id, String status) async {
    try {
      await widget.api.updateIncidentStatus(id, status);
      await _refresh(silent: true);
      if (!mounted) return;
      _message(
        'Status insiden ditukar kepada ${_incidentStatusLabel(status)}.',
      );
    } catch (error) {
      if (!mounted) return;
      _message(error.toString());
    }
  }

  Future<void> _showIncidentImages(Map<String, dynamic> incident) async {
    final id = (incident['id'] as num?)?.toInt();
    if (id == null) return;
    showDialog<void>(
      context: context,
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
                return const Center(
                  child: Text('Tiada gambar untuk insiden ini.'),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Bukti Gambar',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
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
                          return InteractiveViewer(
                            child: Image.memory(
                              base64Decode(source.split(',').last),
                              fit: BoxFit.contain,
                            ),
                          );
                        } catch (_) {
                          return const Center(
                            child: Text('Gambar tidak dapat dibaca.'),
                          );
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

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final summary = data?.summary ?? const <String, dynamic>{};
    final guards = data?.guardActivity ?? const <Map<String, dynamic>>[];
    final incidents = data?.incidents ?? const <Map<String, dynamic>>[];
    final sos = data?.sosEvents ?? const <Map<String, dynamic>>[];
    final openIncidents = (summary['openIncidents'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pemantauan Rondaan'),
        actions: [
          IconButton(
            tooltip: 'Peta Langsung (masa semasa)',
            onPressed: _openLiveMap,
            icon: const Icon(Icons.map_rounded),
          ),
          IconButton(
            tooltip: 'Muat semula',
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  children: [
                    _PeriodFilter(
                      mode: _mode,
                      periodLabel: _periodLabel(),
                      onMode: _changeMode,
                      onPickDate: _pickAnchor,
                    ),
                    const SizedBox(height: 12),
                    _OperationsHero(
                      summary: summary,
                      generatedAt: data?.generatedAt,
                      periodLabel: _periodLabel(),
                      onMap: _openLiveMap,
                      onGuards: _showGuardActivity,
                      onComplete: () => _showCoverageDays(
                        title: 'Sesi Lengkap',
                        historyFilter: 'complete',
                        onlyComplete: true,
                      ),
                      onAlerts: _showMissedDetails,
                      onIncidents: () => _scrollTo(_incidentsKey),
                      onUrgent: () => _scrollTo(_incidentsKey),
                      onSos: _openSos,
                    ),
                    const SizedBox(height: 12),
                    _PatrolCoverageOverview(
                      summary: summary,
                      periodLabel: _periodLabel(),
                      onScanned: () =>
                          _showCoverageDays(title: 'Checkpoint Diimbas'),
                      onMissedCheckpoints: _showMissedDetails,
                      onMissedSessions: _showMissedDetails,
                    ),
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: _attendanceKey,
                      child: _AttendanceOverview(
                        summary: data?.attendanceSummary ?? const {},
                        recent: data?.attendanceRecent ?? const [],
                        periodLabel: _periodLabel(),
                        rangeContainsToday: _rangeContainsToday,
                        onDetails: _openAttendance,
                      ),
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
                    const SizedBox(height: 22),
                    _SectionHeader(
                      title: 'Aktiviti Peronda Dalam Tempoh',
                      subtitle:
                          '${guards.length} pengawal mempunyai rekod scan',
                      actionLabel: guards.isEmpty ? null : 'Lihat lanjut',
                      onAction: guards.isEmpty ? null : _showGuardActivity,
                    ),
                    const SizedBox(height: 10),
                    if (guards.isEmpty)
                      const _EmptyState(
                        icon: Icons.shield_outlined,
                        text: 'Tiada aktiviti rondaan dalam tempoh ini.',
                      )
                    else
                      ...guards
                          .take(8)
                          .map(
                            (row) => _GuardActivityCard(
                              row: row,
                              image: _profileImage(row['profilePicture']),
                              dateTimeLabel: _dateTime(row['lastScanAt']),
                              onTap: () {
                                final parsed = DateTime.tryParse(
                                  row['lastScanAt'] as String? ?? '',
                                )?.toLocal();
                                unawaited(
                                  _openHistory(
                                    date: parsed == null
                                        ? _to
                                        : DateTime(
                                            parsed.year,
                                            parsed.month,
                                            parsed.day,
                                          ),
                                    departmentId: (row['departmentId'] as num?)
                                        ?.toInt(),
                                  ),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 22),
                    KeyedSubtree(
                      key: _incidentsKey,
                      child: _SectionHeader(
                        title: 'Insiden Dalam Tempoh',
                        subtitle:
                            '${incidents.length} rekod • $openIncidents masih terbuka',
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (incidents.isEmpty)
                      const _EmptyState(
                        icon: Icons.task_alt_rounded,
                        text: 'Tiada insiden dalam tempoh ini.',
                      )
                    else
                      ...incidents
                          .take(20)
                          .map(
                            (incident) => _IncidentCard(
                              incident: incident,
                              timeLabel: _dateTime(incident['created_at']),
                              onAcknowledge: () => _updateIncident(
                                (incident['id'] as num).toInt(),
                                'acknowledged',
                              ),
                              onResolve: () => _updateIncident(
                                (incident['id'] as num).toInt(),
                                'resolved',
                              ),
                              onImages:
                                  ((incident['image_count'] as num?)?.toInt() ??
                                          0) ==
                                      0
                                  ? null
                                  : () => _showIncidentImages(incident),
                            ),
                          ),
                    const SizedBox(height: 22),
                    _SectionHeader(
                      title: 'SOS Dalam Tempoh',
                      subtitle: '${sos.length} rekod',
                      actionLabel: 'Pengurusan SOS',
                      onAction: _openSos,
                    ),
                    const SizedBox(height: 10),
                    if (sos.isEmpty)
                      const _EmptyState(
                        icon: Icons.sos_outlined,
                        text: 'Tiada SOS dalam tempoh ini.',
                      )
                    else
                      ...sos
                          .take(15)
                          .map(
                            (row) => Card(
                              color: const Color(0xFF2C1116),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0x33FF7675),
                                  child: Icon(
                                    Icons.sos_rounded,
                                    color: Color(0xFFFF7675),
                                  ),
                                ),
                                title: Text(
                                  row['nama'] as String? ?? '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  '${row['jabatan'] ?? '-'} • ${_dateTime(row['triggered_at'])}\n${row['note'] ?? 'Tiada catatan'}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: _openSos,
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

class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({
    required this.mode,
    required this.periodLabel,
    required this.onMode,
    required this.onPickDate,
  });

  final _PeriodMode mode;
  final String periodLabel;
  final ValueChanged<_PeriodMode> onMode;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tempoh Pemantauan',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(periodLabel),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Pilih tarikh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<_PeriodMode>(
            segments: const [
              ButtonSegment(
                value: _PeriodMode.day,
                label: Text('Day'),
                icon: Icon(Icons.today_rounded),
              ),
              ButtonSegment(
                value: _PeriodMode.week,
                label: Text('Week'),
                icon: Icon(Icons.view_week_rounded),
              ),
              ButtonSegment(
                value: _PeriodMode.month,
                label: Text('Month'),
                icon: Icon(Icons.calendar_view_month_rounded),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (value) => onMode(value.first),
          ),
        ],
      ),
    ),
  );
}

class _OperationsHero extends StatelessWidget {
  const _OperationsHero({
    required this.summary,
    required this.generatedAt,
    required this.periodLabel,
    required this.onMap,
    required this.onGuards,
    required this.onComplete,
    required this.onAlerts,
    required this.onIncidents,
    required this.onUrgent,
    required this.onSos,
  });

  final Map<String, dynamic> summary;
  final DateTime? generatedAt;
  final String periodLabel;
  final VoidCallback onMap;
  final VoidCallback onGuards;
  final VoidCallback onComplete;
  final VoidCallback onAlerts;
  final VoidCallback onIncidents;
  final VoidCallback onUrgent;
  final VoidCallback onSos;

  int _value(String key) => (summary[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final alerts = _value('alerts');
    final incidents = _value('incidentCount');
    final sos = _value('sosCount');
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
                      'Pusat Pemantauan Operasi',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$periodLabel${generatedAt == null ? '' : ' • dikemas kini ${_clock(generatedAt!)}'}',
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Peta Langsung (masa semasa)',
                onPressed: onMap,
                icon: const Icon(Icons.map_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 650
                  ? (constraints.maxWidth - 18) / 3
                  : (constraints.maxWidth - 9) / 2;
              return Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: _value('patrolUsers'),
                      label: 'PERONDA AKTIF',
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF74B9FF),
                      onTap: onGuards,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: _value('completeSessions'),
                      label: 'SESI LENGKAP',
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF55E6C1),
                      onTap: onComplete,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: alerts,
                      label: 'AMARAN',
                      icon: Icons.warning_amber_rounded,
                      color: alerts > 0
                          ? const Color(0xFFFF7675)
                          : const Color(0xFFB2BEC3),
                      onTap: onAlerts,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: incidents,
                      label: 'INSIDEN',
                      icon: Icons.report_problem_rounded,
                      color: const Color(0xFFFDCB6E),
                      onTap: onIncidents,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: _value('urgentIncidents'),
                      label: 'SEGERA',
                      icon: Icons.priority_high_rounded,
                      color: const Color(0xFFFF9F43),
                      onTap: onUrgent,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      value: sos,
                      label: 'SOS',
                      icon: Icons.sos_rounded,
                      color: sos > 0
                          ? const Color(0xFFFF7675)
                          : const Color(0xFFB2BEC3),
                      onTap: onSos,
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
    required this.onTap,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.09),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
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
            const SizedBox(height: 3),
            const Text('Lihat lanjut', style: TextStyle(fontSize: 8)),
          ],
        ),
      ),
    ),
  );
}

class _PatrolCoverageOverview extends StatelessWidget {
  const _PatrolCoverageOverview({
    required this.summary,
    required this.periodLabel,
    required this.onScanned,
    required this.onMissedCheckpoints,
    required this.onMissedSessions,
  });

  final Map<String, dynamic> summary;
  final String periodLabel;
  final VoidCallback onScanned;
  final VoidCallback onMissedCheckpoints;
  final VoidCallback onMissedSessions;

  int _value(String key) => (summary[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final missedSessions = _value('missedSessions');
    final missedCheckpoints = _value('missedCheckpoints');
    final scanned = _value('scannedCheckpoints');
    final due = _value('dueCheckpoints');
    final completedScanned = _value('completedScannedCheckpoints');
    final coverage = due <= 0 ? 0.0 : (completedScanned / due).clamp(0.0, 1.0);
    final coveragePercent = (coverage * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_rounded),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Liputan Rondaan • $periodLabel',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    due <= 0
                        ? 'BELUM ADA SESI TAMAT'
                        : '$coveragePercent% LIPUTAN',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Hanya sesi yang telah tamat dalam tempoh dipilih dikira sebagai perlu siap atau terlepas. Sesi semasa tidak ditanda terlepas sehingga tamat.',
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: coverage, minHeight: 9),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _CoverageMetric(
                        icon: Icons.nfc_rounded,
                        value: scanned,
                        label: 'CHECKPOINT DIIMBAS',
                        onTap: onScanned,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CoverageMetric(
                        icon: Icons.location_off_rounded,
                        value: missedCheckpoints,
                        label: 'CHECKPOINT TERLEPAS',
                        onTap: onMissedCheckpoints,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CoverageMetric(
                        icon: Icons.event_busy_rounded,
                        value: missedSessions,
                        label: 'SESI TERLEPAS',
                        onTap: onMissedSessions,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverageMetric extends StatelessWidget {
  const _CoverageMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.035),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _AttendanceOverview extends StatelessWidget {
  const _AttendanceOverview({
    required this.summary,
    required this.recent,
    required this.periodLabel,
    required this.rangeContainsToday,
    required this.onDetails,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> recent;
  final String periodLabel;
  final bool rangeContainsToday;
  final VoidCallback onDetails;

  String _time(Object? value) {
    final date = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kehadiran • $periodLabel',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      '“Hadir” = pengawal unik yang mempunyai sekurang-kurangnya satu punch MASUK dalam tempoh.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Sejarah Kehadiran'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AttendanceMetric(
                label: 'Hadir Dalam Tempoh',
                value: '${summary['presentUsers'] ?? 0}',
              ),
              _AttendanceMetric(
                label: 'Hari-Pengawal Hadir',
                value: '${summary['attendanceDays'] ?? 0}',
              ),
              _AttendanceMetric(
                label: 'Tiada Rekod Dalam Tempoh',
                value: '${summary['absentUsers'] ?? 0}',
              ),
              _AttendanceMetric(
                label: 'Semak Wajah',
                value: '${summary['faceReviewRequired'] ?? 0}',
              ),
              if (rangeContainsToday)
                _AttendanceMetric(
                  label: 'Masih IN Hari Ini',
                  value: '${summary['currentlyIn'] ?? 0}',
                ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            ...recent
                .take(5)
                .map(
                  (row) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      row['punchType'] == 'IN'
                          ? Icons.login_rounded
                          : Icons.logout_rounded,
                    ),
                    title: Text(
                      row['userName'] as String? ?? 'Pengguna',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${row['department'] ?? '-'} • ${row['punchType'] == 'IN' ? 'MASUK' : 'KELUAR'} ${_time(row['punchedAt'])}',
                    ),
                    trailing: Text(
                      row['faceScore'] == null
                          ? 'SEMAK'
                          : '${(row['faceScore'] as num).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    onTap: onDetails,
                  ),
                ),
          ],
        ],
      ),
    ),
  );
}

class _AttendanceMetric extends StatelessWidget {
  const _AttendanceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(width: 5),
        Text(label),
      ],
    ),
  );
}

class _GuardActivityCard extends StatelessWidget {
  const _GuardActivityCard({
    required this.row,
    required this.image,
    required this.dateTimeLabel,
    required this.onTap,
  });

  final Map<String, dynamic> row;
  final ImageProvider<Object>? image;
  final String dateTimeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundImage: image,
        child: image == null ? const Icon(Icons.person_rounded) : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              row['nama'] as String? ?? 'Pengawal',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (row['currentlyPatrolling'] == true)
            const Chip(
              visualDensity: VisualDensity.compact,
              label: Text('SEDANG MERONDA'),
            ),
        ],
      ),
      subtitle: Text(
        '${row['jabatan'] ?? '-'} • ${row['scanCount'] ?? 0} scan • ${row['sessionCount'] ?? 0} sesi • ${row['activeDays'] ?? 0} hari\nScan terakhir: $dateTimeLabel',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.timeLabel,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onImages,
  });

  final Map<String, dynamic> incident;
  final String timeLabel;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback? onImages;

  @override
  Widget build(BuildContext context) {
    final severity = incident['severity'] as String? ?? 'normal';
    final status = incident['status'] as String? ?? 'open';
    final imageCount = (incident['image_count'] as num?)?.toInt() ?? 0;
    final color = severity == 'urgent'
        ? const Color(0xFFFF7675)
        : severity == 'important'
        ? const Color(0xFFFDCB6E)
        : const Color(0xFF74B9FF);
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
                          '${incident['category'] ?? 'Insiden'} • ${_incidentSeverityLabel(severity)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${incident['nama'] ?? '-'} • ${incident['jabatan'] ?? '-'} • ${incident['checkpoint_name'] ?? 'Tanpa checkpoint'}',
                        ),
                        Text(
                          timeLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _incidentStatusLabel(status),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
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
                      label: const Text('Ambil Maklum'),
                    ),
                  if (status != 'resolved')
                    FilledButton.tonalIcon(
                      onPressed: onResolve,
                      icon: const Icon(Icons.task_alt_rounded),
                      label: const Text('Selesaikan'),
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
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      if (onAction != null)
        TextButton(
          onPressed: onAction,
          child: Text(actionLabel ?? 'Lihat lanjut'),
        ),
    ],
  );
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(),
            Expanded(child: child),
          ],
        ),
      ),
    ),
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

String _incidentStatusLabel(String status) => switch (status.toLowerCase()) {
  'open' => 'TERBUKA',
  'acknowledged' => 'DIAMBIL MAKLUM',
  'resolved' => 'SELESAI',
  _ => status.toUpperCase(),
};

String _incidentSeverityLabel(String severity) =>
    switch (severity.toLowerCase()) {
      'urgent' => 'SEGERA',
      'important' => 'PENTING',
      'normal' => 'BIASA',
      _ => severity.toUpperCase(),
    };
