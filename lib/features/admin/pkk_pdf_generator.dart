import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PkkPdfGenerator {
  static const months = <String>[
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

  static final PdfColor _headerBlue = PdfColor.fromInt(0xff0d6efd);

  static Future<Uint8List> generatePkk2({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) async {
    final department = _department(data);
    final sessions = _attendanceSessions(
      data['attendance'] as List<dynamic>? ?? const [],
    );
    final guards = _guards(data, sessions);
    final guardPages = guards.isEmpty
        ? const <List<_GuardMeta>>[<_GuardMeta>[]]
        : <List<_GuardMeta>>[
            for (var start = 0; start < guards.length; start += 4)
              guards.skip(start).take(4).toList(),
          ];

    final requiredByShift = _requiredGuardsByShift(sessions, month, year);
    final doc = pw.Document();
    for (final pageGuards in guardPages) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),
          build: (_) => _pkk2Page(
            department: department,
            month: month,
            year: year,
            guards: pageGuards,
            sessions: sessions,
            requiredShift1: requiredByShift[1] ?? 0,
            requiredShift2: requiredByShift[2] ?? 0,
          ),
        ),
      );
    }
    return doc.save();
  }

  static Future<Uint8List> generatePkk3({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) async {
    final department = _department(data);
    final sessions = _attendanceSessions(
      data['attendance'] as List<dynamic>? ?? const [],
    );
    final guards = _guards(data, sessions);
    final effectiveGuards = guards.isEmpty
        ? const <_GuardMeta>[_GuardMeta(id: 0, name: '-', noPk: '')]
        : guards;

    final doc = pw.Document();
    for (final guard in effectiveGuards) {
      final guardSessions =
          sessions
              .where(
                (item) =>
                    item.userId == guard.id &&
                    item.start.year == year &&
                    item.start.month == month,
              )
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));

      const rowsPerPage = 20;
      final pageCount = math.max(
        1,
        (guardSessions.length / rowsPerPage).ceil(),
      );
      for (var page = 0; page < pageCount; page++) {
        final pageRows = guardSessions
            .skip(page * rowsPerPage)
            .take(rowsPerPage)
            .toList();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(24, 18, 24, 20),
            build: (_) => _pkk3Page(
              department: department,
              month: month,
              year: year,
              guard: guard,
              sessions: pageRows,
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  static Future<Uint8List> generatePkk4({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) async {
    final department = _department(data);
    final scans = <Map<String, dynamic>>[];
    for (final item in data['scans'] as List<dynamic>? ?? const []) {
      final row = Map<String, dynamic>.from(item as Map);
      final at = _malaysiaDateTime(row['scanned_at']?.toString());
      if (at != null && at.year == year && at.month == month) {
        row['_local'] = at;
        scans.add(row);
      }
    }

    var checkpoints = <Map<String, dynamic>>[];
    for (final item in data['checkpoints'] as List<dynamic>? ?? const []) {
      final row = Map<String, dynamic>.from(item as Map);
      if (row['active'] == false || row['active'] == 0) continue;
      checkpoints.add(row);
    }
    if (checkpoints.isEmpty) {
      final derived = <int, Map<String, dynamic>>{};
      for (final row in scans) {
        final id = (row['checkpoint_id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        derived[id] = {
          'id': id,
          'name': row['checkpoint_name'] ?? 'Checkpoint',
          'position': row['checkpoint_position'] ?? 9999,
        };
      }
      checkpoints = derived.values.toList();
    }
    checkpoints.sort((a, b) {
      final pa = (a['position'] as num?)?.toInt() ?? 9999;
      final pb = (b['position'] as num?)?.toInt() ?? 9999;
      if (pa != pb) return pa.compareTo(pb);
      return '${a['name']}'.compareTo('${b['name']}');
    });

    final rows = <_Pkk4Row>[];
    final activeDays =
        scans.map((row) => (row['_local'] as DateTime).day).toSet().toList()
          ..sort();
    for (final day in activeDays) {
      for (
        var checkpointIndex = 0;
        checkpointIndex < checkpoints.length;
        checkpointIndex++
      ) {
        final checkpoint = checkpoints[checkpointIndex];
        final checkpointId = (checkpoint['id'] as num?)?.toInt() ?? 0;
        final slots = List<String>.filled(12, '');
        for (var slot = 0; slot < 12; slot++) {
          DateTime? earliest;
          for (final scan in scans) {
            if ((scan['checkpoint_id'] as num?)?.toInt() != checkpointId) {
              continue;
            }
            final at = scan['_local'] as DateTime;
            if (at.day != day || (at.hour ~/ 2) != slot) continue;
            if (earliest == null || at.isBefore(earliest)) earliest = at;
          }
          if (earliest != null) slots[slot] = _hhmm(earliest);
        }
        rows.add(
          _Pkk4Row(
            day: day,
            showDate: checkpointIndex == 0,
            checkpoint: (checkpoint['name'] ?? 'Checkpoint').toString(),
            slots: slots,
          ),
        );
      }
    }

    final pages = _splitPkk4Rows(rows);
    final doc = pw.Document();
    for (var page = 0; page < pages.length; page++) {
      final isFirst = page == 0;
      final isContinuation = page > 0;
      final isSinglePage = pages.length == 1;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 18),
          build: (_) => _pkk4Page(
            department: department,
            month: month,
            year: year,
            rows: pages[page],
            showDocumentHeader: isFirst,
            showSignatureArea: isSinglePage || isContinuation,
          ),
        ),
      );
    }
    return doc.save();
  }

  static pw.Widget _pkk2Page({
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<_GuardMeta> guards,
    required List<_GuardSession> sessions,
    required int requiredShift1,
    required int requiredShift2,
  }) {
    final days = DateTime(year, month + 1, 0).day;
    final blocks = <List<int>>[
      for (var start = 1; start <= 31; start += 10)
        <int>[
          for (var day = start; day <= math.min(start + 9, 31); day++)
            if (day <= days) day,
        ],
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'PKK 2 (BAGI KONTRAK YANG BERMULA PADA 1 JANUARI 2019 DAN SETERUSNYA) - PINDAAN JULAI 2019',
            style: pw.TextStyle(fontSize: 5.2, fontWeight: pw.FontWeight.bold),
          ),
        ),
        _centerTitle(
          'BORANG PENGESAHAN BILANGAN PENGAWAL DAN REKOD KEHADIRAN PENGAWAL KESELAMATAN',
          7.5,
        ),
        _centerTitle(
          'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
          7.1,
        ),
        _centerTitle('DI BAWAH KEMENTERIAN PENDIDIKAN MALAYSIA', 7.1),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'BULAN: ${months[month - 1]}       TAHUN: $year',
            style: pw.TextStyle(fontSize: 6.4, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        _pkk2Meta(department),
        pw.SizedBox(height: 2),
        _pkk2ContractSummary(requiredShift1, requiredShift2),
        pw.SizedBox(height: 2),
        pw.Text(
          '3   SENARAI NAMA PENGAWAL KESELAMATAN YANG BERTUGAS MENGIKUT SYIF',
          style: pw.TextStyle(fontSize: 5.6, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        for (var i = 0; i < blocks.length; i++) ...[
          _pkk2AttendanceBlock(
            days: blocks[i],
            guards: guards,
            sessions: sessions,
            month: month,
            year: year,
          ),
          if (i != blocks.length - 1) pw.SizedBox(height: 1.0),
        ],
        pw.SizedBox(height: 1.5),
        _pkk2Note(),
        pw.SizedBox(height: 1),
        _sprmNotice(),
        pw.SizedBox(height: 1.5),
        _signatureRow(),
      ],
    );
  }

  static pw.Widget _pkk2Meta(Map<String, dynamic> department) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              flex: 3,
              child: _plainMeta(
                'NAMA SYARIKAT:',
                '${department['companyName'] ?? ''}',
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              flex: 2,
              child: _plainMeta('ZON:', '${department['zone'] ?? ''}'),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        _plainMeta(
          'SEKOLAH/INSTITUSI PENDIDIKAN:',
          '${department['name'] ?? ''}',
        ),
      ],
    );
  }

  static pw.Widget _pkk2ContractSummary(
    int requiredShift1,
    int requiredShift2,
  ) {
    pw.Widget shiftCount() => pw.Expanded(
      child: pw.Column(
        children: [
          _boxText(
            '1   BILANGAN PENGAWAL KESELAMATAN YANG DITETAPKAN MENGIKUT SYIF DALAM DOKUMEN PERJANJIAN KONTRAK\n(Sila nyatakan)',
            fontSize: 5.1,
            bold: true,
            height: 18,
            fill: PdfColors.grey300,
          ),
          pw.Row(
            children: [
              pw.Expanded(child: _boxText('SYIF 1', height: 9)),
              pw.Expanded(child: _boxText('SYIF 2', height: 9)),
              pw.Expanded(child: _boxText('SYIF 3', height: 9)),
            ],
          ),
          pw.Row(
            children: [
              pw.Expanded(child: _boxText('$requiredShift1', height: 9)),
              pw.Expanded(child: _boxText('$requiredShift2', height: 9)),
              pw.Expanded(child: _boxText('', height: 9)),
            ],
          ),
        ],
      ),
    );

    pw.Widget shiftHours() => pw.Expanded(
      child: pw.Column(
        children: [
          _boxText(
            '2   WAKTU BERTUGAS SETIAP SYIF\n(Sila nyatakan)',
            fontSize: 5.1,
            bold: true,
            height: 18,
            fill: PdfColors.grey300,
          ),
          pw.Row(
            children: [
              pw.Expanded(child: _boxText('SYIF 1', height: 9)),
              pw.Expanded(child: _boxText('SYIF 2', height: 9)),
              pw.Expanded(child: _boxText('SYIF 3', height: 9)),
            ],
          ),
          pw.Row(
            children: [
              pw.Expanded(
                child: _boxText('Jam 08.00 hingga\njam 20.00', height: 13),
              ),
              pw.Expanded(
                child: _boxText('Jam 20.00 hingga\njam 08.00', height: 13),
              ),
              pw.Expanded(
                child: _boxText('Jam ______ hingga\njam ______', height: 13),
              ),
            ],
          ),
        ],
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [shiftCount(), pw.SizedBox(width: 18), shiftHours()],
    );
  }

  static pw.Widget _pkk2AttendanceBlock({
    required List<int> days,
    required List<_GuardMeta> guards,
    required List<_GuardSession> sessions,
    required int month,
    required int year,
  }) {
    final paddedDays = <int?>[
      ...days,
      ...List<int?>.filled(10 - days.length, null),
    ];

    pw.Widget sideCell(
      String text, {
      double? height,
      bool bold = false,
      PdfColor? fill,
      pw.Alignment alignment = pw.Alignment.center,
    }) {
      return pw.Container(
        height: height,
        alignment: alignment,
        decoration: pw.BoxDecoration(
          color: fill,
          border: pw.Border.all(width: 0.35),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.2),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 3.9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    pw.Widget dailyHeader() => pw.Column(
      children: [
        pw.Row(
          children: [
            for (final day in paddedDays)
              pw.Expanded(
                child: _boxText(
                  day == null ? '' : '$day',
                  height: 11,
                  fontSize: 3.6,
                  fill: PdfColors.grey200,
                ),
              ),
          ],
        ),
        pw.Row(
          children: [
            for (final day in paddedDays)
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: _boxText(
                        day == null ? '' : 'SYIF 1',
                        height: 11,
                        fontSize: 3.6,
                        fill: PdfColors.grey200,
                      ),
                    ),
                    pw.Expanded(
                      child: _boxText(
                        day == null ? '' : 'SYIF 2',
                        height: 11,
                        fontSize: 3.6,
                        fill: PdfColors.grey200,
                      ),
                    ),
                    pw.Expanded(
                      child: _boxText(
                        day == null ? '' : 'SYIF 3',
                        height: 11,
                        fontSize: 3.6,
                        fill: PdfColors.grey200,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );

    pw.Widget guardDaily(_GuardMeta guard) {
      return pw.Row(
        children: [
          for (final day in paddedDays)
            pw.Expanded(
              child: pw.Row(
                children: [
                  for (var shift = 1; shift <= 3; shift++)
                    pw.Expanded(
                      child: _boxText(
                        day == null
                            ? ''
                            : _hoursFor(
                                sessions,
                                guard.id,
                                year,
                                month,
                                day,
                                shift,
                              ),
                        height: 9,
                        fontSize: 3.7,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    const headerText = 'BILANGAN JAM BERTUGAS MENGIKUT TARIKH DAN SYIF';
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.SizedBox(
              width: 22,
              child: sideCell(
                'BIL.',
                height: 18,
                bold: true,
                fill: PdfColors.grey200,
              ),
            ),
            pw.SizedBox(
              width: 155,
              child: sideCell(
                'NAMA PENGAWAL KESELAMATAN\n(TERMASUK PENGAWAL KESELAMATAN GANTIAN)\n(Sila pastikan nama adalah SAMA dengan Borang PKK 3 dan Borang PKK 5)',
                height: 18,
                bold: true,
                fill: PdfColors.grey200,
              ),
            ),
            pw.SizedBox(
              width: 54,
              child: sideCell(
                'STATUS PENGAWAL KESELAMATAN\n(Tandakan pada ruangan berkaitan)',
                height: 18,
                bold: true,
                fill: PdfColors.grey200,
              ),
            ),
            pw.Expanded(
              child: sideCell(
                headerText,
                height: 18,
                bold: true,
                fill: PdfColors.grey200,
              ),
            ),
          ],
        ),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 22,
              child: sideCell('', height: 16, fill: PdfColors.grey200),
            ),
            pw.SizedBox(
              width: 155,
              child: sideCell('', height: 16, fill: PdfColors.grey200),
            ),
            pw.SizedBox(
              width: 54,
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: sideCell(
                      'TETAP',
                      height: 16,
                      bold: true,
                      fill: PdfColors.grey200,
                    ),
                  ),
                  pw.Expanded(
                    child: sideCell(
                      'GANTIAN',
                      height: 16,
                      bold: true,
                      fill: PdfColors.grey200,
                    ),
                  ),
                ],
              ),
            ),
            pw.Expanded(child: dailyHeader()),
          ],
        ),
        for (var index = 0; index < 4; index++)
          pw.Row(
            children: [
              pw.SizedBox(
                width: 22,
                child: sideCell(
                  index < guards.length ? '${index + 1}' : '',
                  height: 9,
                ),
              ),
              pw.SizedBox(
                width: 155,
                child: sideCell(
                  index < guards.length ? guards[index].name : '',
                  height: 9,
                  alignment: pw.Alignment.centerLeft,
                ),
              ),
              pw.SizedBox(
                width: 54,
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: sideCell(
                        index < guards.length ? 'X' : '',
                        height: 9,
                      ),
                    ),
                    pw.Expanded(child: sideCell('', height: 9)),
                  ],
                ),
              ),
              pw.Expanded(
                child: index < guards.length
                    ? guardDaily(guards[index])
                    : pw.Row(
                        children: [
                          for (var i = 0; i < 30; i++)
                            pw.Expanded(
                              child: _boxText('', height: 9, fontSize: 3.7),
                            ),
                        ],
                      ),
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _pkk3Page({
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required _GuardMeta guard,
    required List<_GuardSession> sessions,
  }) {
    final rows = <List<String>>[];
    for (var i = 0; i < sessions.length; i++) {
      final item = sessions[i];
      rows.add([
        '${i + 1}',
        _ymd(item.start),
        _ymdhms(item.start),
        item.end == null ? '' : _ymdhms(item.end!),
        '',
        '',
      ]);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'PKK 3 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2024 DAN SETERUSNYA)',
            style: pw.TextStyle(fontSize: 5.2, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 5),
        _centerTitle(
          'BORANG PENGESAHAN KEHADIRAN PENGAWAL BERDASARKAN REKOD KEHADIRAN PENGAWAL KESELAMATAN',
          7.6,
        ),
        _centerTitle(
          'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
          7.3,
        ),
        _centerTitle('DI BAWAH KEMENTERIAN PENDIDIKAN MALAYSIA', 7.3),
        pw.SizedBox(height: 9),
        _pkk3Meta(department, guard, month, year),
        pw.SizedBox(height: 7),
        _pkk3Table(rows),
        pw.SizedBox(height: 8),
        _pkk3Note(),
        pw.SizedBox(height: 6),
        _sprmNotice(),
        pw.SizedBox(height: 8),
        _signatureRow(),
      ],
    );
  }

  static pw.Widget _pkk3Meta(
    Map<String, dynamic> department,
    _GuardMeta guard,
    int month,
    int year,
  ) {
    final left = [
      ['BULAN:', months[month - 1]],
      ['NEGERI:', _state(department)],
      ['NAMA SYARIKAT:', '${department['companyName'] ?? ''}'],
      ['SEKOLAH/INSTITUSI PENDIDIKAN:', '${department['name'] ?? ''}'],
    ];
    final right = [
      ['TAHUN:', '$year'],
      ['ZON:', '${department['zone'] ?? ''}'],
      ['', ''],
      ['NAMA PEKERJA:', guard.name],
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            children: [for (final pair in left) _inlineMeta(pair[0], pair[1])],
          ),
        ),
        pw.SizedBox(width: 28),
        pw.Expanded(
          child: pw.Column(
            children: [for (final pair in right) _inlineMeta(pair[0], pair[1])],
          ),
        ),
      ],
    );
  }

  static pw.Widget _pkk3Table(List<List<String>> rows) {
    const widths = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(0.55),
      1: pw.FlexColumnWidth(1.45),
      2: pw.FlexColumnWidth(2.4),
      3: pw.FlexColumnWidth(2.4),
      4: pw.FlexColumnWidth(1.45),
      5: pw.FlexColumnWidth(1.45),
    };
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _headerBlue),
          children: [
            for (final header in const [
              'BIL',
              'TARIKH',
              'MASUK',
              'KELUAR',
              'TANDA TANGAN',
              'CATATAN',
            ])
              pw.Container(
                height: 18,
                alignment: pw.Alignment.centerLeft,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                child: pw.Text(
                  header,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 6.1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              for (var i = 0; i < row.length; i++)
                pw.Container(
                  height: 14.2,
                  alignment: i == 0
                      ? pw.Alignment.center
                      : pw.Alignment.centerLeft,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: pw.Text(
                    row[i],
                    style: const pw.TextStyle(fontSize: 5.8),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _pkk4Page({
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<_Pkk4Row> rows,
    required bool showDocumentHeader,
    required bool showSignatureArea,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (showDocumentHeader) ...[
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'PKK 4 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2024 DAN SETERUSNYA)',
              style: pw.TextStyle(
                fontSize: 5.2,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 7),
          _centerTitle(
            'BORANG PENGESAHAN PELAKSANAAN RONDAAN DAN CLOCKING',
            7.6,
          ),
          _centerTitle(
            'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
            7.2,
          ),
          _centerTitle('DI BAWAH KEMENTERIAN PENDIDIKAN MALAYSIA', 7.2),
          pw.SizedBox(height: 11),
          _pkk4Meta(department, month, year),
          pw.SizedBox(height: 10),
        ],
        _pkk4Header(),
        for (final row in rows) _pkk4DataRow(row, month, year),
        if (showSignatureArea) ...[
          pw.SizedBox(height: 8),
          _pkk4Note(),
          pw.SizedBox(height: 6),
          _sprmNotice(),
          pw.SizedBox(height: 8),
          _signatureRow(),
        ],
      ],
    );
  }

  static pw.Widget _pkk4Meta(
    Map<String, dynamic> department,
    int month,
    int year,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(child: _inlineMeta('BULAN:', months[month - 1])),
            pw.SizedBox(width: 30),
            pw.Expanded(child: _inlineMeta('TAHUN:', '$year')),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(child: _inlineMeta('NEGERI:', _state(department))),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: _inlineMeta('ZON:', '${department['zone'] ?? ''}'),
            ),
          ],
        ),
        _inlineMeta('NAMA SYARIKAT:', '${department['companyName'] ?? ''}'),
        _inlineMeta(
          'SEKOLAH/INSTITUSI PENDIDIKAN:',
          '${department['name'] ?? ''}',
        ),
      ],
    );
  }

  static pw.Widget _pkk4Header() {
    const totalHeight = 38.0;
    pw.Widget blueCell(String text, {double? height}) => pw.Container(
      height: height,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: _headerBlue,
        border: pw.Border.all(color: PdfColors.black, width: 0.45),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 5.1,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 48, child: blueCell('Date', height: totalHeight)),
        pw.SizedBox(
          width: 54,
          child: blueCell('Checkpoint', height: totalHeight),
        ),
        pw.Expanded(
          child: pw.Column(
            children: [
              blueCell('Session', height: 16),
              pw.Row(
                children: [
                  for (final label in const [
                    '00:00 -\n02:00',
                    '02:00 -\n04:00',
                    '04:00 -\n06:00',
                    '06:00 -\n08:00',
                    '08:00 -\n10:00',
                    '10:00 -\n12:00',
                    '12:00 -\n14:00',
                    '14:00 -\n16:00',
                    '16:00 -\n18:00',
                    '18:00 -\n20:00',
                    '20:00 -\n22:00',
                    '22:00 -\n00:00',
                  ])
                    pw.Expanded(child: blueCell(label, height: 22)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(
          width: 52,
          child: blueCell('Summarize', height: totalHeight),
        ),
      ],
    );
  }

  static pw.Widget _pkk4DataRow(_Pkk4Row row, int month, int year) {
    pw.Widget cell(
      String text, {
      pw.Alignment alignment = pw.Alignment.center,
      double? width,
    }) {
      final widget = pw.Container(
        height: 11.7,
        alignment: alignment,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.4),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 1),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 4.85)),
      );
      return width == null ? widget : pw.SizedBox(width: width, child: widget);
    }

    final complete = row.slots.where((value) => value.isNotEmpty).length;
    return pw.Row(
      children: [
        cell(
          row.showDate ? _dmy(DateTime(year, month, row.day)) : '',
          width: 48,
        ),
        cell(row.checkpoint, width: 54, alignment: pw.Alignment.centerLeft),
        pw.Expanded(
          child: pw.Row(
            children: [
              for (final value in row.slots)
                pw.Expanded(child: cell(value.isEmpty ? '-' : value)),
            ],
          ),
        ),
        cell('$complete / 12', width: 52),
      ],
    );
  }

  static List<List<_Pkk4Row>> _splitPkk4Rows(List<_Pkk4Row> rows) {
    if (rows.isEmpty) return const <List<_Pkk4Row>>[<_Pkk4Row>[]];
    if (rows.length <= 34) return <List<_Pkk4Row>>[rows];

    final pages = <List<_Pkk4Row>>[];
    var offset = 0;
    final firstCount = math.min(51, rows.length);
    pages.add(rows.take(firstCount).toList());
    offset = firstCount;
    while (offset < rows.length) {
      final count = math.min(34, rows.length - offset);
      pages.add(rows.skip(offset).take(count).toList());
      offset += count;
    }
    return pages;
  }

  static pw.Widget _pkk2Note() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nota:',
        style: pw.TextStyle(fontSize: 4.5, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Pengawal Keselamatan dibenarkan bertugas lebih masa tidak melebihi 12 jam sehari dengan syarat mematuhi bilangan Pengawal Keselamatan yang ditetapkan bagi setiap syif. Sila tambah ruangan senarai nama Pengawal dan Pengawal gantian sekiranya ruangan tidak mencukupi. Sekiranya helaian tambahan digunakan, ruangan tandatangan Penyedia, Penyemak dan Pengesah hendaklah disediakan di setiap helaian.',
        style: const pw.TextStyle(fontSize: 4.05),
        textAlign: pw.TextAlign.justify,
      ),
    ],
  );

  static pw.Widget _pkk3Note() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nota:',
        style: pw.TextStyle(fontSize: 4.6, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Sila tampal salinan Buku Rekod Kehadiran Pengawal, Kad Perakam Waktu (Punch Card) atau Laporan Kehadiran Biometrik (Thumb Print) dengan kemas dan teratur. Sila pastikan bahawa Pengawal Keselamatan, cetakan tarikh dan masa kehadiran pada waktu bertugas mengikut syif adalah jelas. Sila pastikan nama Pengawal Keselamatan pada salinan Buku Rekod Kehadiran Pengawal, Kad Perakam Waktu (Punch Card) atau Laporan Kehadiran Biometrik (Thumb Print) adalah SAMA dengan yang dinyatakan dalam Borang PKK 2 dan Borang PKK 5. Sila gunakan lampiran tambahan sekiranya ruangan tidak mencukupi. Sekiranya helaian tambahan digunakan, ruangan tandatangan Penyedia, Penyemak dan Pengesah hendaklah disediakan di setiap helaian.',
        style: const pw.TextStyle(fontSize: 4.05),
        textAlign: pw.TextAlign.justify,
      ),
    ],
  );

  static pw.Widget _pkk4Note() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Nota:',
        style: pw.TextStyle(fontSize: 4.5, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Sila tampal slip/laporan watchman clock dengan kemas dan teratur serta pastikan bahawa cetakan tarikh dan masa clocking adalah jelas. Sila gunakan lampiran tambahan sekiranya ruangan tidak mencukupi. Sekiranya helaian tambahan digunakan, ruangan tandatangan Penyedia, Penyemak dan Pengesah hendaklah disediakan di setiap helaian.',
        style: const pw.TextStyle(fontSize: 4.0),
        textAlign: pw.TextAlign.justify,
      ),
    ],
  );

  static pw.Widget _sprmNotice() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Peringatan:',
        style: pw.TextStyle(fontSize: 4.6, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Seksyen 18, Akta SPRM: "Seseorang melakukan kesalahan jika dia memberi seseorang ejen, atau sebagai seorang ejen dia menggunakan, dengan niat hendak memperdayakan prinsipalnya, apa-apa resit, akaun atau dokumen lain yang berkenaan dengan prinsipalnya itu mempunyai kepentingan, dan yang dia mempunyai sebab untuk mempercayai mengandungi apa-apa pernyataan yang palsu atau silap atau tidak lengkap tentang apa-apa butir matan, dan yang dimaksudkan untuk mengelirukan prinsipalnya."',
        style: const pw.TextStyle(fontSize: 3.95),
        textAlign: pw.TextAlign.justify,
      ),
    ],
  );

  static pw.Widget _signatureRow() {
    pw.Widget signatureBlock(String title, List<String> lines) {
      return pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 4.7,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              '------------------------------------------------------------',
              style: const pw.TextStyle(fontSize: 4.1),
            ),
            for (final line in lines)
              pw.Text(line, style: const pw.TextStyle(fontSize: 3.75)),
          ],
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        signatureBlock('Disediakan Oleh:', const [
          '(Tandatangan & Cap Rasmi)',
          'Pengurus/Wakil Syarikat',
          'Tarikh:',
        ]),
        pw.SizedBox(width: 18),
        signatureBlock('Disemak Oleh:', const [
          '(Tandatangan & Cap Rasmi)',
          'Tarikh:',
          'Institusi Pendidikan: Pegawai/Penolong Jurutera/Pegawai Eksekutif Kanan/Ketua Unit Khidmat Pengurusan',
          'Sekolah: Guru Penolong Kanan Pentadbiran',
          'Pusat Kokurikulum: Pegawai/Penyelia Pusat Kokurikulum',
          'KIP/KRG: Pegawai Pentadbir/Pegawai Aset/Pegawai Pembangunan JPN atau Institusi Pendidikan atau PPD',
        ]),
        pw.SizedBox(width: 18),
        signatureBlock('Disahkan Oleh:', const [
          '(Tandatangan & Cap Rasmi)',
          'Tarikh:',
          'Institusi Pendidikan: Ketua/Timbalan Ketua Sekolah/Pengarah/Timbalan Pengarah JPN atau Institusi/Pegawai Pendidikan Daerah (PPD)/Timbalan PPD/Ketua Sektor',
          'Sekolah: Pengetua/Guru Besar',
          'Pusat Kokurikulum: Ketua Unit Pusat Kokurikulum',
          'KIP/KRG: Ketua/Timbalan Ketua Sekolah/Pengarah/Timbalan Pengarah JPN atau Institusi/PPD/Timbalan PPD/Ketua Sektor',
        ]),
      ],
    );
  }

  static pw.Widget _centerTitle(String text, double fontSize) => pw.Center(
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _plainMeta(String label, String value) => pw.Row(
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(fontSize: 5.3, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(width: 3),
      pw.Expanded(
        child: pw.Text(value, style: const pw.TextStyle(fontSize: 5.3)),
      ),
    ],
  );

  static pw.Widget _inlineMeta(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      children: [
        if (label.isNotEmpty)
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 6.1, fontWeight: pw.FontWeight.bold),
          ),
        if (label.isNotEmpty) pw.SizedBox(width: 3),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 6.0)),
        ),
      ],
    ),
  );

  static pw.Widget _boxText(
    String text, {
    double fontSize = 4.5,
    double? height,
    bool bold = false,
    PdfColor? fill,
  }) => pw.Container(
    height: height,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      color: fill,
      border: pw.Border.all(width: 0.35),
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  static Map<String, dynamic> _department(Map<String, dynamic> data) {
    final raw = data['department'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static String _state(Map<String, dynamic> department) {
    final value = (department['state'] ?? '').toString().trim();
    return value.isEmpty ? 'KEDAH' : value.toUpperCase();
  }

  static List<_GuardMeta> _guards(
    Map<String, dynamic> data,
    List<_GuardSession> sessions,
  ) {
    final result = <int, _GuardMeta>{};
    for (final item in data['guards'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final jawatan = (row['jawatan'] ?? '').toString().toLowerCase();
      if (jawatan != 'patrol' && jawatan != 'supervisor') continue;
      final id = (row['id'] as num?)?.toInt() ?? 0;
      if (id <= 0) continue;
      result[id] = _GuardMeta(
        id: id,
        name: (row['nama'] ?? '-').toString(),
        noPk: (row['no_pk'] ?? '').toString(),
      );
    }
    for (final session in sessions) {
      result.putIfAbsent(
        session.userId,
        () => _GuardMeta(
          id: session.userId,
          name: session.name,
          noPk: session.noPk,
        ),
      );
    }
    final guards = result.values.toList()
      ..sort((a, b) {
        final aNo = int.tryParse(a.noPk);
        final bNo = int.tryParse(b.noPk);
        if (aNo != null && bNo != null && aNo != bNo) {
          return aNo.compareTo(bNo);
        }
        return a.name.compareTo(b.name);
      });
    return guards;
  }

  static List<_GuardSession> _attendanceSessions(List<dynamic> raw) {
    final byUser = <int, List<Map<String, dynamic>>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final jawatan = (row['jawatan'] ?? '').toString().toLowerCase();
      if (jawatan != 'patrol' && jawatan != 'supervisor') continue;
      final at = _malaysiaDateTime(row['punched_at']?.toString());
      if (at == null) continue;
      final userId = (row['user_id'] as num?)?.toInt() ?? 0;
      if (userId <= 0) continue;
      byUser.putIfAbsent(userId, () => <Map<String, dynamic>>[]).add({
        ...row,
        '_local': at,
      });
    }

    final result = <_GuardSession>[];
    for (final entry in byUser.entries) {
      final rows = entry.value
        ..sort(
          (a, b) =>
              (a['_local'] as DateTime).compareTo(b['_local'] as DateTime),
        );
      Map<String, dynamic>? pendingIn;
      for (final row in rows) {
        final type = (row['punch_type'] ?? '').toString().toUpperCase();
        if (type == 'IN') {
          if (pendingIn != null) {
            result.add(_sessionFromPunch(pendingIn, null));
          }
          pendingIn = row;
          continue;
        }
        if (type == 'OUT' && pendingIn != null) {
          final outAt = row['_local'] as DateTime;
          final inAt = pendingIn['_local'] as DateTime;
          if (outAt.isAfter(inAt)) {
            result.add(_sessionFromPunch(pendingIn, row));
            pendingIn = null;
          }
        }
      }
      if (pendingIn != null) result.add(_sessionFromPunch(pendingIn, null));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static _GuardSession _sessionFromPunch(
    Map<String, dynamic> input,
    Map<String, dynamic>? output,
  ) {
    final start = input['_local'] as DateTime;
    final end = output?['_local'] as DateTime?;
    final shift = start.hour >= 6 && start.hour < 18 ? 1 : 2;
    return _GuardSession(
      userId: (input['user_id'] as num?)?.toInt() ?? 0,
      name: (input['nama'] ?? '-').toString(),
      noPk: (input['no_pk'] ?? '').toString(),
      start: start,
      end: end,
      shift: shift,
    );
  }

  static Map<int, int> _requiredGuardsByShift(
    List<_GuardSession> sessions,
    int month,
    int year,
  ) {
    final counts = <int, int>{1: 0, 2: 0};
    final byDay = <String, Set<int>>{};
    for (final session in sessions) {
      if (session.start.year != year || session.start.month != month) continue;
      final key = '${session.start.day}|${session.shift}';
      byDay.putIfAbsent(key, () => <int>{}).add(session.userId);
    }
    for (final entry in byDay.entries) {
      final shift = int.tryParse(entry.key.split('|').last) ?? 1;
      counts[shift] = math.max(counts[shift] ?? 0, entry.value.length);
    }
    return counts;
  }

  static String _hoursFor(
    List<_GuardSession> sessions,
    int userId,
    int year,
    int month,
    int day,
    int shift,
  ) {
    var minutes = 0;
    for (final session in sessions) {
      if (session.userId != userId ||
          session.start.year != year ||
          session.start.month != month ||
          session.start.day != day ||
          session.shift != shift ||
          session.end == null) {
        continue;
      }
      minutes += session.end!.difference(session.start).inMinutes;
    }
    if (minutes <= 0) return '';
    final hours = minutes / 60;
    if ((hours - hours.round()).abs() < 0.05) return '${hours.round()}';
    return hours.toStringAsFixed(1);
  }

  static DateTime? _malaysiaDateTime(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 8));
  }

  static String _hhmm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _ymd(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _ymdhms(DateTime value) =>
      '${_ymd(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

  static String _dmy(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year.toString().padLeft(4, '0')}';
}

class _GuardMeta {
  const _GuardMeta({required this.id, required this.name, required this.noPk});
  final int id;
  final String name;
  final String noPk;
}

class _GuardSession {
  const _GuardSession({
    required this.userId,
    required this.name,
    required this.noPk,
    required this.start,
    required this.end,
    required this.shift,
  });
  final int userId;
  final String name;
  final String noPk;
  final DateTime start;
  final DateTime? end;
  final int shift;
}

class _Pkk4Row {
  const _Pkk4Row({
    required this.day,
    required this.showDate,
    required this.checkpoint,
    required this.slots,
  });
  final int day;
  final bool showDate;
  final String checkpoint;
  final List<String> slots;
}
