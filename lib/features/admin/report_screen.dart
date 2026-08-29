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
  static const _months = <String>[
    'JANUARI',
    'FEBRUARI',
    'MAC',
    'APRIL',
    'MEI',
    'JUN',
    'JULAI',
    'OGOS',
    'SEPTEMBER',
    'OKTOBER',
    'NOVEMBER',
    'DISEMBER',
  ];

  static const _weekdays = <String>[
    'ISNIN',
    'SELASA',
    'RABU',
    'KHAMIS',
    'JUMAAT',
    'SABTU',
    'AHAD',
  ];

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

  DateTime get _from => DateTime(_year, _month, 1);
  DateTime get _to => DateTime(_year, _month + 1, 0);

  String _date(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _dateKey(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _time(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  DateTime? _malaysiaDateTime(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 8));
  }

  String _formatIso(String? value) {
    final parsed = _malaysiaDateTime(value);
    if (parsed == null) return value ?? '-';
    return '${_date(parsed)} ${_time(parsed)}:${parsed.second.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> _reportData({required bool requireDepartment}) async {
    if (requireDepartment && _departmentId == null) {
      throw Exception('Pilih satu Jabatan sebelum menjana borang BPPA.');
    }
    return widget.api.getAdminReport(
      _from,
      _to,
      departmentId: _departmentId,
    );
  }

  Future<void> _runGenerator(Future<void> Function() generator) async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      await generator();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generatePdf() => _runGenerator(() async {
        final data = await _reportData(requireDepartment: false);
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
              pw.Text('Bulan: ${_months[_month - 1]} $_year'),
              pw.Text('Tempoh: ${_date(_from)} hingga ${_date(_to)}'),
              pw.Text('Jabatan: ${selectedDepartment?['name'] ?? 'Semua Jabatan'}'),
              pw.SizedBox(height: 16),
              pw.Row(
                children: [
                  _stat('Pengguna aktif', '${summary['activeUsers'] ?? 0}'),
                  pw.SizedBox(width: 8),
                  _stat('Jumlah imbasan', '${summary['totalScans'] ?? scans.length}'),
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
                pw.Text('Tiada rekod imbasan dalam bulan ini.')
              else
                pw.TableHelper.fromTextArray(
                  headers: const ['Masa', 'Pengguna', 'Jabatan', 'Checkpoint', 'UID'],
                  data: scans.map((item) {
                    final row = Map<String, dynamic>.from(item as Map);
                    return [
                      _formatIso(row['scanned_at'] as String?),
                      row['nama'] ?? '-',
                      row['jabatan'] ?? '-',
                      row['checkpoint_name'] ?? '-',
                      row['nfc_uid'] ?? '-',
                    ];
                  }).toList(),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Rekod SOS',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              if (sosEvents.isEmpty)
                pw.Text('Tiada rekod SOS dalam bulan ini.')
              else
                pw.TableHelper.fromTextArray(
                  headers: const ['Masa', 'Pengguna', 'Jabatan', 'Nota'],
                  data: sosEvents.map((item) {
                    final row = Map<String, dynamic>.from(item as Map);
                    return [
                      _formatIso(row['triggered_at'] as String?),
                      row['nama'] ?? '-',
                      row['jabatan'] ?? '-',
                      row['note'] ?? '-',
                    ];
                  }).toList(),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                ),
            ],
          ),
        );

        await Printing.sharePdf(
          bytes: await document.save(),
          filename: 'RimbaKawal_${_year}_${_month.toString().padLeft(2, '0')}.pdf',
        );
      });

  Future<void> _generatePkk2() => _runGenerator(() async {
        final data = await _reportData(requireDepartment: true);
        final attendance = data['attendance'] as List<dynamic>? ?? const [];
        final department = Map<String, dynamic>.from(data['department'] as Map);
        final rowsByDay = <int, Map<int, _AttendanceDayRow>>{};

        for (final item in attendance) {
          final row = Map<String, dynamic>.from(item as Map);
          final punchedAt = _malaysiaDateTime(row['punched_at'] as String?);
          if (punchedAt == null || punchedAt.month != _month || punchedAt.year != _year) continue;
          final userId = (row['user_id'] as num?)?.toInt() ?? 0;
          final dayMap = rowsByDay.putIfAbsent(punchedAt.day, () => <int, _AttendanceDayRow>{});
          final current = dayMap.putIfAbsent(
            userId,
            () => _AttendanceDayRow(name: row['nama']?.toString() ?? '-', firstPunch: punchedAt),
          );
          if (punchedAt.isBefore(current.firstPunch)) current.firstPunch = punchedAt;
          if (row['punch_type'] == 'IN' &&
              (current.inTime == null || punchedAt.isBefore(current.inTime!))) {
            current.inTime = punchedAt;
          }
          if (row['punch_type'] == 'OUT' &&
              (current.outTime == null || punchedAt.isAfter(current.outTime!))) {
            current.outTime = punchedAt;
          }
        }

        for (final entry in rowsByDay.entries) {
          if (entry.value.length > 4) {
            throw Exception(
              'BPPA PKK 2 hanya mempunyai 4 baris pengawal bagi tarikh ${entry.key}. '
              'Terdapat ${entry.value.length} pengawal pada tarikh tersebut.',
            );
          }
        }

        final document = pw.Document();
        document.addPage(_pkk2Page(document, department['name']?.toString() ?? '', 1, 12, rowsByDay));
        document.addPage(_pkk2Page(document, department['name']?.toString() ?? '', 13, 24, rowsByDay));
        document.addPage(_pkk2Page(document, department['name']?.toString() ?? '', 25, 31, rowsByDay));

        await Printing.sharePdf(
          bytes: await document.save(),
          filename: 'BPPA_PKK_2_${_year}_${_month.toString().padLeft(2, '0')}.pdf',
        );
      });

  pw.Page _pkk2Page(
    pw.Document document,
    String institution,
    int startDay,
    int endDay,
    Map<int, Map<int, _AttendanceDayRow>> rowsByDay,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(12, 16, 12, 16),
      build: (context) {
        final tableRows = <pw.TableRow>[
          pw.TableRow(
            children: [
              _cell('TARIKH', bold: true, align: pw.Alignment.center, height: 27),
              _cell('NAMA', bold: true, align: pw.Alignment.center, height: 27),
              _cell('NO. PK', bold: true, align: pw.Alignment.center, height: 27),
              _cell('SYIF', bold: true, align: pw.Alignment.center, height: 27),
              _cell('WAKTU\nMASUK', bold: true, align: pw.Alignment.center, height: 27),
              _cell('WAKTU\nKELUAR', bold: true, align: pw.Alignment.center, height: 27),
              _cell('T.TANGAN', bold: true, align: pw.Alignment.center, height: 27),
              _cell('CATATAN', bold: true, align: pw.Alignment.center, height: 27),
            ],
          ),
        ];

        for (var day = startDay; day <= endDay; day++) {
          final guardRows = (rowsByDay[day]?.values.toList() ?? <_AttendanceDayRow>[])
            ..sort((a, b) => a.firstPunch.compareTo(b.firstPunch));
          for (var slot = 0; slot < 4; slot++) {
            final guard = slot < guardRows.length ? guardRows[slot] : null;
            tableRows.add(
              pw.TableRow(
                children: [
                  _cell(slot == 0 ? '$day' : '', align: pw.Alignment.center, height: 10.6),
                  _cell('${String.fromCharCode(97 + slot)}. ${guard?.name ?? ''}', height: 10.6),
                  _cell('', height: 10.6),
                  _cell('', align: pw.Alignment.center, height: 10.6),
                  _cell(guard?.inTime == null ? '' : _time(guard!.inTime!), align: pw.Alignment.center, height: 10.6),
                  _cell(guard?.outTime == null ? '' : _time(guard!.outTime!), align: pw.Alignment.center, height: 10.6),
                  _cell('', height: 10.6),
                  _cell('', height: 10.6),
                ],
              ),
            );
          }
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('BPPA PKK 2', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text('BORANG KEHADIRAN PENGAWAL', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('BAGI PERKHIDMATAN KAWALAN KESELAMATAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('DI INSTITUSI-INSTITUSI PENDIDIKAN / SEKOLAH DI BAWAH', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('KEMENTERIAN PELAJARAN MALAYSIA', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 13),
            _fieldLine('INSTITUSI/SEKOLAH :', institution),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(child: _fieldLine('BULAN :', _months[_month - 1])),
                pw.SizedBox(width: 80),
                pw.Expanded(child: _fieldLine('TAHUN :', '$_year')),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(child: _fieldLine('NAMA SYARIKAT :', '')),
                pw.SizedBox(width: 80),
                pw.Expanded(child: _fieldLine('ZON :', '')),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(width: 0.65, color: PdfColors.black),
              columnWidths: const {
                0: pw.FixedColumnWidth(42),
                1: pw.FlexColumnWidth(2.25),
                2: pw.FlexColumnWidth(1.35),
                3: pw.FixedColumnWidth(34),
                4: pw.FixedColumnWidth(52),
                5: pw.FixedColumnWidth(52),
                6: pw.FixedColumnWidth(58),
                7: pw.FixedColumnWidth(65),
              },
              children: tableRows,
            ),
            if (endDay == 31) ...[
              pw.SizedBox(height: 7),
              pw.Text('Nota :       SYIF', style: const pw.TextStyle(fontSize: 6.8)),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 55, top: 2),
                child: pw.Text('1- SIANG\n2- MALAM', style: const pw.TextStyle(fontSize: 6.8, lineSpacing: 2)),
              ),
            ],
            pw.Spacer(),
            _pkk2Signatures(),
          ],
        );
      },
    );
  }

  Future<void> _generatePkk3() => _runGenerator(() async {
        final data = await _reportData(requireDepartment: true);
        final scansRaw = data['scans'] as List<dynamic>? ?? const [];
        final department = Map<String, dynamic>.from(data['department'] as Map);
        final scansByDay = <String, List<Map<String, dynamic>>>{};
        for (final item in scansRaw) {
          final row = Map<String, dynamic>.from(item as Map);
          final scannedAt = _malaysiaDateTime(row['scanned_at'] as String?);
          if (scannedAt == null || scannedAt.year != _year || scannedAt.month != _month) continue;
          scansByDay.putIfAbsent(_dateKey(scannedAt), () => <Map<String, dynamic>>[]).add(row);
        }
        for (final rows in scansByDay.values) {
          rows.sort((a, b) {
            final sessionA = (a['session_index'] as num?)?.toInt() ?? 0;
            final sessionB = (b['session_index'] as num?)?.toInt() ?? 0;
            if (sessionA != sessionB) return sessionA.compareTo(sessionB);
            final positionA = (a['checkpoint_position'] as num?)?.toInt() ?? 9999;
            final positionB = (b['checkpoint_position'] as num?)?.toInt() ?? 9999;
            if (positionA != positionB) return positionA.compareTo(positionB);
            final timeA = _malaysiaDateTime(a['scanned_at'] as String?) ?? DateTime(1970);
            final timeB = _malaysiaDateTime(b['scanned_at'] as String?) ?? DateTime(1970);
            return timeA.compareTo(timeB);
          });
        }

        final first = _from;
        var monday = first.subtract(Duration(days: first.weekday - DateTime.monday));
        final last = _to;
        final document = pw.Document();
        var weekNo = 1;
        while (!monday.isAfter(last)) {
          document.addPage(
            _pkk3Page(
              department['name']?.toString() ?? '',
              monday,
              weekNo,
              scansByDay,
            ),
          );
          monday = monday.add(const Duration(days: 7));
          weekNo++;
        }

        await Printing.sharePdf(
          bytes: await document.save(),
          filename: 'BPPA_PKK_3_${_year}_${_month.toString().padLeft(2, '0')}.pdf',
        );
      });

  pw.Page _pkk3Page(
    String institution,
    DateTime monday,
    int weekNo,
    Map<String, List<Map<String, dynamic>>> scansByDay,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(12, 12, 12, 14),
      build: (context) {
        final dates = List<DateTime>.generate(7, (index) => monday.add(Duration(days: index)));
        final bodyCells = <pw.Widget>[];
        for (final date in dates) {
          final inMonth = date.year == _year && date.month == _month;
          final rows = inMonth ? (scansByDay[_dateKey(date)] ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
          bodyCells.add(
            pw.Container(
              height: 375,
              padding: const pw.EdgeInsets.fromLTRB(3, 4, 3, 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final row in rows)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1.5),
                      child: pw.Text(
                        _checkpointLine(row),
                        style: const pw.TextStyle(fontSize: 5.8, lineSpacing: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('BPPA PKK 3', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Center(child: pw.Text('LAPORAN PELAKSANAAN KUNCI JAM "WATCHMAN CLOCK"', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('BAGI PERKHIDMATAN KAWALAN KESELAMATAN', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('DI INSTITUSI-INSTITUSI PENDIDIKAN / SEKOLAH DI BAWAH KEMENTERIAN PENDIDIKAN MALAYSIA', style: pw.TextStyle(fontSize: 8.3, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 17),
            _fieldLine('INSTITUSI/SEKOLAH :', institution),
            pw.SizedBox(height: 11),
            pw.Row(
              children: [
                pw.Expanded(child: _fieldLine('BULAN/TAHUN :', '${_months[_month - 1]} / $_year')),
                pw.SizedBox(width: 55),
                pw.Expanded(child: _fieldLine('MINGGU :', '$weekNo')),
              ],
            ),
            pw.SizedBox(height: 9),
            pw.Row(
              children: [
                pw.Expanded(child: _fieldLine('NAMA SYARIKAT :', '')),
                pw.SizedBox(width: 55),
                pw.Expanded(child: _fieldLine('ZON :', '')),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(width: 0.65, color: PdfColors.black),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.yellow),
                  children: [
                    for (final name in _weekdays)
                      _cell(name, height: 22, bold: true, align: pw.Alignment.center, fontSize: 7.2),
                  ],
                ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.yellow),
                  children: [
                    for (final date in dates)
                      _cell(
                        date.year == _year && date.month == _month ? 'TARIKH : ${date.day}' : 'TARIKH :',
                        height: 22,
                        bold: true,
                        align: pw.Alignment.center,
                        fontSize: 7,
                      ),
                  ],
                ),
                pw.TableRow(children: bodyCells),
              ],
            ),
            pw.SizedBox(height: 8),
            _pkk3Signatures(),
            pw.SizedBox(height: 8),
            pw.Text('Peringatan :', style: pw.TextStyle(fontSize: 6.2, fontStyle: pw.FontStyle.italic)),
            pw.Text(
              'Seksyen 18, Akta SPRM : "Seseorang melakukan kesalahan jika dia memberi seseorang ejen, atau sebagai seorang ejen dia menggunakan, dengan niat hendak memperdayakan prinsipalnya, apa-apa resit, akaun atau dokumen lain yang berkenaan dengan prinsipalnya itu mempunyai kepentingan, dan yang dia mempunyai sebab untuk mempercayai mengandungi apa-apa pernyataan yang palsu atau silap atau tidak lengkap tentang apa-apa pernyataan yang palsu atau silap atau tidak lengkap tentang apa-apa butir matan, dan yang dimaksudkan untuk mengelirukan prinsipalnya."',
              style: pw.TextStyle(fontSize: 5.7, fontStyle: pw.FontStyle.italic),
              textAlign: pw.TextAlign.justify,
            ),
          ],
        );
      },
    );
  }

  String _checkpointLine(Map<String, dynamic> row) {
    final scannedAt = _malaysiaDateTime(row['scanned_at'] as String?);
    final position = (row['checkpoint_position'] as num?)?.toInt();
    final name = row['checkpoint_name']?.toString().trim() ?? '';
    final cp = position == null ? 'Checkpoint' : 'Checkpoint $position';
    final suffix = name.isEmpty || name.toLowerCase() == cp.toLowerCase() ? '' : ' - $name';
    return '${scannedAt == null ? '--:--' : _time(scannedAt)} $cp$suffix';
  }

  pw.Widget _fieldLine(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: pw.Container(
            height: 12,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.45)),
            ),
            alignment: pw.Alignment.bottomLeft,
            padding: const pw.EdgeInsets.only(left: 3, bottom: 1),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 7)),
          ),
        ),
      ],
    );
  }

  pw.Widget _cell(
    String text, {
    double height = 14,
    bool bold = false,
    double fontSize = 6.8,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      height: height,
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: align == pw.Alignment.center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  pw.Widget _pkk2Signatures() {
    pw.Widget signature(String heading, String role) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(heading, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 34),
              pw.Text('............................................................', style: const pw.TextStyle(fontSize: 6.5)),
              pw.Text('(Tandatangan & Cop Rasmi)', style: const pw.TextStyle(fontSize: 6.2)),
              pw.Text(role, style: const pw.TextStyle(fontSize: 6.2)),
              pw.Text('Tarikh:', style: const pw.TextStyle(fontSize: 6.2)),
            ],
          ),
        );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        signature('Disediakan oleh:', 'Pengurus/ Wakil Syarikat'),
        pw.SizedBox(width: 90),
        signature('Disahkan oleh:', 'Pengarah/ PPD/ Pengetua/Guru Besar/\nPenghulu(KIP/KRG/Rumah guru)'),
      ],
    );
  }

  pw.Widget _pkk3Signatures() {
    pw.Widget signature(String heading, String role) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(heading, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 29),
              pw.Text('............................................................', style: const pw.TextStyle(fontSize: 6.2)),
              pw.Text('(Tandatangan & Cop Rasmi)', style: const pw.TextStyle(fontSize: 6)),
              pw.Text(role, style: const pw.TextStyle(fontSize: 5.9)),
              pw.Text('Tarikh :', style: const pw.TextStyle(fontSize: 5.9)),
            ],
          ),
        );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        signature('Disediakan Oleh :', 'Pengurus/Wakil Syarikat'),
        pw.SizedBox(width: 22),
        signature('Disemak Oleh :', 'Guru/Penyelia /Pegawai Sekolah atau Institusi'),
        pw.SizedBox(width: 22),
        signature('Disahkan Oleh :', 'Pengarah/PPD/Pengetua/Guru Besar'),
      ],
    );
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
            pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final years = List<int>.generate(DateTime.now().year - 2023, (index) => 2024 + index).reversed.toList();
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
                    'Jana Laporan',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text('Pilih bulan dan Jabatan. Borang BPPA dijana mengikut rekod bulan yang dipilih.'),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<int?>(
                    initialValue: _departmentId,
                    decoration: const InputDecoration(
                      labelText: 'Jabatan',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Semua Jabatan')),
                      ..._departments.map(
                        (department) => DropdownMenuItem<int?>(value: department.id, child: Text(department.name)),
                      ),
                    ],
                    onChanged: _loadingDepartments ? null : (value) => setState(() => _departmentId = value),
                  ),
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
                              DropdownMenuItem(value: month, child: Text(_months[month - 1])),
                          ],
                          onChanged: _generating ? null : (value) => setState(() => _month = value ?? _month),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _year,
                          decoration: const InputDecoration(labelText: 'Tahun'),
                          items: years.map((year) => DropdownMenuItem(value: year, child: Text('$year'))).toList(),
                          onChanged: _generating ? null : (value) => setState(() => _year = value ?? _year),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _generating || _loadingDepartments ? null : _generatePdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(_generating ? 'Menjana…' : 'Jana Laporan Rondaan'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _generating || _loadingDepartments ? null : _generatePkk2,
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Jana BPPA PKK 2 — Borang Kehadiran Pengawal'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _generating || _loadingDepartments ? null : _generatePkk3,
                    icon: const Icon(Icons.schedule_rounded),
                    label: const Text('Jana BPPA PKK 3 — Laporan Pelaksanaan Kunci Jam'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nota: Borang BPPA memerlukan satu Jabatan. Medan NAMA SYARIKAT, ZON, NO. PK dan SYIF dibiarkan kosong kerana RimbaKawal belum mempunyai medan khusus tersebut.',
                    style: TextStyle(fontSize: 12),
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

class _AttendanceDayRow {
  _AttendanceDayRow({required this.name, required this.firstPunch});

  final String name;
  DateTime firstPunch;
  DateTime? inTime;
  DateTime? outTime;
}
