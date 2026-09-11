import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import 'pkk_pdf_generator.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({required this.api, this.user, super.key});

  final ApiService api;
  final AppUser? user;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  bool _generating = false;
  bool _loadingDepartments = true;
  String? _error;
  List<DepartmentRecord> _departments = const [];
  int? _departmentId;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final departments = await widget.api.getAdminDepartments();
      if (!mounted) return;
      final active = departments.where((item) => item.active).toList();
      setState(() {
        _departments = active;
        _loadingDepartments = false;
        if (_departmentId == null && active.length == 1) {
          _departmentId = active.first.id;
        }
        if (active.isEmpty) {
          _error = widget.user?.isAdministration == true
              ? 'Tiada sekolah dipautkan kepada syarikat akaun ini.'
              : 'Tiada sekolah aktif ditemui.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingDepartments = false;
      });
    }
  }

  DateTime get _from => DateTime(_year, _month, 1);
  DateTime get _to => DateTime(_year, _month + 1, 0);

  Future<Map<String, dynamic>> _reportData() async {
    if (_departmentId == null) {
      throw Exception('Pilih satu Sekolah sebelum menjana laporan PKK.');
    }
    return widget.api.getAdminReport(_from, _to, departmentId: _departmentId);
  }

  Future<void> _generate(_PkkType type) async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await _reportData();
      final Uint8List bytes = switch (type) {
        _PkkType.pkk2 => await PkkPdfGenerator.generatePkk2(
          data: data,
          month: _month,
          year: _year,
        ),
        _PkkType.pkk3 => await PkkPdfGenerator.generatePkk3(
          data: data,
          month: _month,
          year: _year,
        ),
        _PkkType.pkk4 => await PkkPdfGenerator.generatePkk4(
          data: data,
          month: _month,
          year: _year,
        ),
      };
      if (bytes.isEmpty) throw Exception('Fail PDF tidak berjaya dijana.');

      final month = _month.toString().padLeft(2, '0');
      String? school;
      for (final item in _departments) {
        if (item.id == _departmentId) {
          school = item.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
          break;
        }
      }
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${type.filePrefix}_${school ?? 'SEKOLAH'}_${_year}_$month.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.label} berjaya dijana sebagai PDF.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = List<int>.generate(
      DateTime.now().year - 2023,
      (index) => 2024 + index,
    ).reversed.toList();
    final isCompanyAdmin = widget.user?.isAdministration == true;
    final companyName = widget.user?.companyName ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Jana Laporan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Jana Laporan PKK',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isCompanyAdmin
                        ? 'Pilih mana-mana sekolah di bawah ${companyName.isEmpty ? 'syarikat anda' : companyName}, kemudian jana PKK 2, PKK 3 atau PKK 4.'
                        : 'Jana PKK 2, PKK 3 dan PKK 4 sebagai PDF berdasarkan data sebenar ZPatrol.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<int?>(
                    initialValue: _departmentId,
                    decoration: InputDecoration(
                      labelText: isCompanyAdmin
                          ? 'Sekolah Di Bawah Syarikat'
                          : 'Sekolah',
                      prefixIcon: const Icon(Icons.account_tree_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Pilih Sekolah'),
                      ),
                      ..._departments.map(
                        (department) => DropdownMenuItem<int?>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      ),
                    ],
                    onChanged: _loadingDepartments || _generating
                        ? null
                        : (value) => setState(() => _departmentId = value),
                  ),
                  if (isCompanyAdmin && _departments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_departments.length} sekolah tersedia untuk akaun ini.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _month,
                          decoration: const InputDecoration(
                            labelText: 'Bulan',
                            prefixIcon: Icon(Icons.calendar_month_rounded),
                          ),
                          items: [
                            for (var month = 1; month <= 12; month++)
                              DropdownMenuItem(
                                value: month,
                                child: Text(PkkPdfGenerator.months[month - 1]),
                              ),
                          ],
                          onChanged: _generating
                              ? null
                              : (value) => setState(() => _month = value ?? _month),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _year,
                          decoration: const InputDecoration(labelText: 'Tahun'),
                          items: years
                              .map(
                                (year) => DropdownMenuItem(
                                  value: year,
                                  child: Text('$year'),
                                ),
                              )
                              .toList(),
                          onChanged: _generating
                              ? null
                              : (value) => setState(() => _year = value ?? _year),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _ReportButton(
                    icon: Icons.groups_rounded,
                    title: 'Jana PKK 2 (PDF)',
                    subtitle: 'Pengesahan bilangan pengawal dan rekod kehadiran',
                    enabled: !_generating && !_loadingDepartments && _departmentId != null,
                    onPressed: () => _generate(_PkkType.pkk2),
                  ),
                  const SizedBox(height: 10),
                  _ReportButton(
                    icon: Icons.badge_rounded,
                    title: 'Jana PKK 3 (PDF)',
                    subtitle: 'Pengesahan kehadiran pengawal berdasarkan rekod kehadiran',
                    enabled: !_generating && !_loadingDepartments && _departmentId != null,
                    onPressed: () => _generate(_PkkType.pkk3),
                  ),
                  const SizedBox(height: 10),
                  _ReportButton(
                    icon: Icons.nfc_rounded,
                    title: 'Jana PKK 4 (PDF)',
                    subtitle: 'Pengesahan pelaksanaan rondaan dan clocking',
                    enabled: !_generating && !_loadingDepartments && _departmentId != null,
                    onPressed: () => _generate(_PkkType.pkk4),
                  ),
                  if (_generating) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text(
                      'Menjana PDF daripada data ZPatrol…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PkkType {
  pkk2('PKK 2', 'PKK_2'),
  pkk3('PKK 3', 'PKK_3'),
  pkk4('PKK 4', 'PKK_4');

  const _PkkType(this.label, this.filePrefix);
  final String label;
  final String filePrefix;
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.picture_as_pdf_rounded),
        ],
      ),
    );
  }
}
