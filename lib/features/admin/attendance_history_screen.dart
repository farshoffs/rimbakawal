import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({required this.api, super.key});
  final ApiService api;

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  DateTime _date = DateTime.now();
  int? _departmentId;
  late Future<List<AttendanceRecord>> _records;
  late Future<List<DepartmentRecord>> _departments;

  @override
  void initState() {
    super.initState();
    _departments = widget.api.getAdminDepartments();
    _reload();
  }

  void _reload() => setState(() {
        _records = widget.api.getAdminAttendance(
          _date,
          departmentId: _departmentId,
        );
      });

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      _date = picked;
      _reload();
    }
  }

  Future<void> _showEvidence(AttendanceRecord record) async {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => FutureBuilder<String>(
        future: widget.api.getAttendanceEvidence(record.id),
        builder: (context, snapshot) => AlertDialog(
          title: Text('${record.nama ?? 'Pengguna'} • Bukti muka'),
          content: SizedBox(
            width: 440,
            child: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : snapshot.hasError
                    ? Text(snapshot.error.toString())
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              base64Decode(snapshot.requireData.split(',').last),
                              height: 320,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Skor padanan: ${((record.faceSimilarity ?? 0) * 100).toStringAsFixed(1)}% • '
                            '${record.faceMatched ? 'DISAHKAN' : 'TIDAK SEPADAN'}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String two(int value) => value.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Sejarah Kehadiran')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text('${two(_date.day)}/${two(_date.month)}/${_date.year}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FutureBuilder<List<DepartmentRecord>>(
                    future: _departments,
                    builder: (context, snapshot) => DropdownButtonFormField<int?>(
                      initialValue: _departmentId,
                      decoration: const InputDecoration(labelText: 'Jabatan'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Semua Jabatan')),
                        ...(snapshot.data ?? const <DepartmentRecord>[]).map(
                          (department) => DropdownMenuItem<int?>(
                            value: department.id,
                            child: Text(department.name, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        _departmentId = value;
                        _reload();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AttendanceRecord>>(
              future: _records,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }
                final records = snapshot.data ?? const <AttendanceRecord>[];
                if (records.isEmpty) {
                  return const Center(child: Text('Tiada rekod kehadiran untuk tarikh ini.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final local = record.recordedAt.toLocal();
                    return Card(
                      child: ListTile(
                        onTap: () => _showEvidence(record),
                        leading: CircleAvatar(
                          child: Icon(record.status == 'accepted'
                              ? Icons.verified_user_rounded
                              : Icons.gpp_bad_rounded),
                        ),
                        title: Text(
                          '${record.nama ?? 'Pengguna'} • ${record.eventType == 'in' ? 'MASUK' : 'KELUAR'}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${record.jabatan ?? ''}\n'
                          '${two(local.hour)}:${two(local.minute)} • Jarak ${record.distanceMeters.toStringAsFixed(0)}m • '
                          'Muka ${((record.faceSimilarity ?? 0) * 100).toStringAsFixed(1)}%'
                          '${record.rejectionReason == null ? '' : '\n${record.rejectionReason}'}',
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          record.status == 'accepted' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: record.status == 'accepted' ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
