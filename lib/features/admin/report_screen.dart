import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/api/api_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
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
      setState(() {
        _departments = departments.where((item) => item.active).toList();
        _loadingDepartments = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingDepartments = false;
      });
    }
  }

  String _date(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to.isBefore(_from)) _to = picked;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = picked;
      }
    });
  }

  Future<void> _generatePdf() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await widget.api.getAdminReport(
        _from,
        _to,
        departmentId: _departmentId,
      );
      final scans = data['scans'] as List<dynamic>? ?? const [];
      final sosEvents = data['sosEvents'] as List<dynamic>? ?? const [];
      final summary = data['summary'] as Map<String, dynamic>? ?? const {};
      final selectedDepartment = data['department'] as Map<String, dynamic>?;

      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (context) => [
            pw.Text(
              'RimbaKawal — Laporan Rondaan',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Tempoh: ${_date(_from)} hingga ${_date(_to)}'),
            pw.Text(
              'Jabatan: ${selectedDepartment?['name'] ?? 'Semua Jabatan'}',
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              children: [
                _stat('Pengguna aktif', '${summary['activeUsers'] ?? 0}'),
                pw.SizedBox(width: 8),
                _stat(
                  'Jumlah scan',
                  '${summary['totalScans'] ?? scans.length}',
                ),
                pw.SizedBox(width: 8),
                _stat('SOS', '${summary['sosEvents'] ?? sosEvents.length}'),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Rekod Checkpoint',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (scans.isEmpty)
              pw.Text('Tiada rekod scan dalam tempoh ini.')
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Masa',
                  'Pengguna',
                  'Jabatan',
                  'Titik Pemeriksaan',
                  'UID',
                ],
                data: scans.map((item) {
                  final row = item as Map<String, dynamic>;
                  return [
                    _formatIso(row['scanned_at'] as String?),
                    row['nama'] ?? '-',
                    row['jabatan'] ?? '-',
                    row['checkpoint_name'] ?? '-',
                    row['nfc_uid'] ?? '-',
                  ];
                }).toList(),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Rekod SOS',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (sosEvents.isEmpty)
              pw.Text('Tiada rekod SOS dalam tempoh ini.')
            else
              pw.TableHelper.fromTextArray(
                headers: const ['Masa', 'Pengguna', 'Jabatan', 'Nota'],
                data: sosEvents.map((item) {
                  final row = item as Map<String, dynamic>;
                  return [
                    _formatIso(row['triggered_at'] as String?),
                    row['nama'] ?? '-',
                    row['jabatan'] ?? '-',
                    row['note'] ?? '-',
                  ];
                }).toList(),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
              ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Dijana oleh RimbaKawal. Masa rekod checkpoint datang daripada server.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      );

      final bytes = await document.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'RimbaKawal_${_fileDate(_from)}_${_fileDate(_to)}.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  pw.Widget _stat(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );
  }

  String _formatIso(String? value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} '
        '${two(parsed.hour)}:${two(parsed.minute)}:${two(parsed.second)}';
  }

  String _fileDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
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
                    'Laporan Rondaan PDF',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pilih Jabatan dan julat sehingga 31 hari. PDF merangkumi rekod checkpoint dan event SOS.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<int?>(
                    initialValue: _departmentId,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Jabatan',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Semua Jabatan'),
                      ),
                      ..._departments.map(
                        (department) => DropdownMenuItem<int?>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      ),
                    ],
                    onChanged: _loadingDepartments
                        ? null
                        : (value) => setState(() => _departmentId = value),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(from: true),
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: Text('Dari ${_date(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(from: false),
                          icon: const Icon(Icons.event_rounded),
                          label: Text('Hingga ${_date(_to)}'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _generating || _loadingDepartments
                        ? null
                        : _generatePdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(_generating ? 'Menjana…' : 'Jana / Simpan PDF'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
