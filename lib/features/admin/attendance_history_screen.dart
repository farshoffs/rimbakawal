import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({
    required this.api,
    this.initialDate,
    super.key,
  });

  final ApiService api;
  final DateTime? initialDate;

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late DateTime _date;
  late Future<AttendanceAdminData> _future;
  late Future<List<DepartmentRecord>> _departmentsFuture;
  int _departmentFilterId = -1;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _date = DateTime(initial.year, initial.month, initial.day);
    _departmentsFuture = widget.api.getAdminDepartments();
    _future = widget.api.getAdminAttendance(_date);
  }

  void _refresh() => setState(
    () => _future = widget.api.getAdminAttendance(
      _date,
      departmentId: _departmentFilterId == -1 ? null : _departmentFilterId,
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _date,
    );
    if (picked != null) {
      _date = picked;
      _refresh();
    }
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Color _faceColor(String status) => switch (status) {
    'matched' => const Color(0xFF00B894),
    'different' => const Color(0xFFFF7675),
    _ => const Color(0xFFFDCB6E),
  };

  ImageProvider<Object>? _image(String? source) {
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

  Future<void> _showDetail(AttendanceRecord record) async {
    var current = record;
    var savingReview = false;
    final profile = _image(record.profilePicture);
    final selfie = _image(record.selfieData);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Detail Kehadiran',
                          style: Theme.of(dialogContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${current.userName ?? 'Pengguna'} • ${current.department ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${current.punchType == 'IN' ? 'MASUK' : 'KELUAR'} • ${_time(current.punchedAt)} • ${current.distanceMeters.toStringAsFixed(0)}m dari pusat',
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _PhotoPanel(
                          title: 'Gambar Profil',
                          image: profile,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PhotoPanel(
                          title: 'Selfie Punch',
                          image: selfie,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.face_retouching_natural_rounded,
                        text: 'Status: ${current.faceStatus}',
                      ),
                      _InfoChip(
                        icon: Icons.analytics_rounded,
                        text: 'Skor: ${current.faceScore?.round() ?? '-'}%',
                      ),
                      _InfoChip(
                        icon: Icons.gps_fixed_rounded,
                        text:
                            'GPS ±${current.accuracyMeters?.toStringAsFixed(0) ?? '-'}m',
                      ),
                      _InfoChip(
                        icon: Icons.location_on_rounded,
                        text:
                            '${current.latitude.toStringAsFixed(6)}, ${current.longitude.toStringAsFixed(6)}',
                      ),
                      if (current.isReviewed)
                        _InfoChip(
                          icon: Icons.verified_rounded,
                          text:
                              'Disemak${current.reviewedByName == null ? '' : ' oleh ${current.reviewedByName}'}',
                        ),
                    ],
                  ),
                  if (current.faceReason != null &&
                      current.faceReason!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Catatan pengecaman: ${current.faceReason}'),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: current.isReviewed || savingReview
                        ? null
                        : () async {
                            setDialogState(() => savingReview = true);
                            try {
                              final updated = await widget.api
                                  .reviewAttendanceRecord(current.id);
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                current = updated;
                                savingReview = false;
                              });
                              _refresh();
                            } catch (error) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() => savingReview = false);
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                    icon: Icon(
                      current.isReviewed
                          ? Icons.verified_rounded
                          : Icons.task_alt_rounded,
                    ),
                    label: Text(
                      current.isReviewed
                          ? 'TELAH DISEMAK'
                          : savingReview
                          ? 'MENYIMPAN…'
                          : 'DISEMAK',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sejarah Kehadiran'),
        actions: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(_dateLabel(_date)),
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<AttendanceAdminData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString()),
              ),
            );
          }
          final data = snapshot.data!;
          final summary = data.summary;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: [
                FutureBuilder<List<DepartmentRecord>>(
                  future: _departmentsFuture,
                  builder: (context, departmentSnapshot) {
                    final departments =
                        (departmentSnapshot.data ?? const <DepartmentRecord>[])
                            .where((department) => department.active)
                            .toList();
                    return DropdownButtonFormField<int>(
                      initialValue: _departmentFilterId,
                      decoration: const InputDecoration(
                        labelText: 'Filter Sekolah',
                        prefixIcon: Icon(Icons.school_rounded),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: -1,
                          child: Text('Semua Sekolah'),
                        ),
                        ...departments.map(
                          (department) => DropdownMenuItem<int>(
                            value: department.id,
                            child: Text(department.name),
                          ),
                        ),
                      ],
                      onChanged:
                          departmentSnapshot.connectionState ==
                              ConnectionState.waiting
                          ? null
                          : (value) {
                              _departmentFilterId = value ?? -1;
                              _refresh();
                            },
                    );
                  },
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SummaryCard(
                      label: 'Hadir',
                      value: '${summary['presentUsers'] ?? 0}',
                      icon: Icons.how_to_reg_rounded,
                    ),
                    _SummaryCard(
                      label: 'Dalam Kawasan',
                      value: '${summary['currentlyIn'] ?? 0}',
                      icon: Icons.location_on_rounded,
                    ),
                    _SummaryCard(
                      label: 'Tidak Hadir',
                      value: '${summary['absentUsers'] ?? 0}',
                      icon: Icons.person_off_rounded,
                    ),
                    _SummaryCard(
                      label: 'Semak Wajah',
                      value: '${summary['faceReviewRequired'] ?? 0}',
                      icon: Icons.face_retouching_natural_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (data.records.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Tiada rekod kehadiran pada tarikh ini.'),
                    ),
                  )
                else
                  ...data.records.map((record) {
                    final color = _faceColor(record.faceStatus);
                    return Card(
                      child: ListTile(
                        onTap: () => _showDetail(record),
                        leading: CircleAvatar(
                          backgroundImage: _image(record.profilePicture),
                          child: _image(record.profilePicture) == null
                              ? const Icon(Icons.person_rounded)
                              : null,
                        ),
                        title: Text(
                          record.userName ?? 'Pengguna',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${record.department ?? '-'} • ${record.punchType == 'IN' ? 'MASUK' : 'KELUAR'} ${_time(record.punchedAt)} • ${record.distanceMeters.toStringAsFixed(0)}m',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            record.faceScore == null
                                ? 'SEMAK'
                                : '${record.faceScore!.round()}%',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({required this.title, required this.image});
  final String title;
  final ImageProvider<Object>? image;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: image == null
              ? Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(
                    Icons.image_not_supported_rounded,
                    size: 42,
                  ),
                )
              : Image(image: image!, fit: BoxFit.cover),
        ),
      ),
    ],
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 16), label: Text(text));
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
