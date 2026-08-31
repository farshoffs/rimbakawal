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

  static Future<Uint8List> generatePkk2({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) async {
    final department = _department(data);
    final sessions = _attendanceSessions(
      data['attendance'] as List<dynamic>? ?? const [],
    );
    final days = DateTime(year, month + 1, 0).day;
    final actual = <int, Map<int, Set<int>>>{};

    for (final session in sessions) {
      if (session.start.year != year || session.start.month != month) continue;
      actual
          .putIfAbsent(session.start.day, () => <int, Set<int>>{})
          .putIfAbsent(session.shift, () => <int>{})
          .add(session.userId);
    }

    var requiredShift1 = 0;
    var requiredShift2 = 0;
    for (final day in actual.values) {
      if ((day[1]?.length ?? 0) > requiredShift1) {
        requiredShift1 = day[1]!.length;
      }
      if ((day[2]?.length ?? 0) > requiredShift2) {
        requiredShift2 = day[2]!.length;
      }
    }

    final doc = pw.Document();
    final pages = <List<int>>[
      List<int>.generate(days > 30 ? 30 : days, (index) => index + 1),
      if (days == 31) const [31],
    ];
    for (final pageDays in pages) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(18, 15, 18, 14),
          build: (_) => _pkk2Page(
            department: department,
            month: month,
            year: year,
            pageDays: pageDays,
            actual: actual,
            requiredShift1: requiredShift1,
            requiredShift2: requiredShift2,
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
    final guardNames = <int, String>{};
    final guardStatus = <int, String>{};
    for (final session in sessions) {
      if (session.start.year != year || session.start.month != month) continue;
      guardNames[session.userId] = session.name;
      guardStatus[session.userId] = 'TETAP';
    }
    final ids = guardNames.keys.toList()
      ..sort((a, b) => guardNames[a]!.compareTo(guardNames[b]!));
    final pages = ids.isEmpty ? 1 : ((ids.length + 2) ~/ 3);
    final doc = pw.Document();

    for (var page = 0; page < pages; page++) {
      final pageIds = ids.skip(page * 3).take(3).toList();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(12, 12, 12, 12),
          build: (_) => _pkk3Page(
            department: department,
            month: month,
            year: year,
            guardIds: pageIds,
            guardNames: guardNames,
            guardStatus: guardStatus,
            sessions: sessions,
          ),
        ),
      );
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
      final active = row['active'];
      if (active == false || active == 0) continue;
      checkpoints.add(row);
    }
    if (checkpoints.isEmpty) {
      final derived = <int, Map<String, dynamic>>{};
      for (final row in scans) {
        final id = (row['checkpoint_id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        derived[id] = {
          'id': id,
          'name': row['checkpoint_name'] ?? 'GUARDTOUR POINT',
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
    final days = DateTime(year, month + 1, 0).day;
    for (var day = 1; day <= days; day++) {
      for (final checkpoint in checkpoints) {
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
          if (earliest != null) slots[slot] = _time(earliest);
        }
        rows.add(
          _Pkk4Row(
            day: day,
            checkpoint: (checkpoint['name'] ?? 'GUARDTOUR POINT').toString(),
            slots: slots,
          ),
        );
      }
    }

    const rowsPerPage = 20;
    final pageCount = rows.isEmpty
        ? 1
        : ((rows.length + rowsPerPage - 1) ~/ rowsPerPage);
    final doc = pw.Document();
    for (var page = 0; page < pageCount; page++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(9, 10, 9, 10),
          build: (_) => _pkk4Page(
            department: department,
            month: month,
            year: year,
            rows: rows.skip(page * rowsPerPage).take(rowsPerPage).toList(),
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
    required List<int> pageDays,
    required Map<int, Map<int, Set<int>>> actual,
    required int requiredShift1,
    required int requiredShift2,
  }) {
    final blocks = <List<int>>[];
    for (var start = 0; start < pageDays.length; start += 10) {
      blocks.add(pageDays.skip(start).take(10).toList());
    }
    while (blocks.length < 3) {
      blocks.add(const []);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _cornerLabel(
          'PKK 2 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2025 DAN SETERUSNYA)',
        ),
        _mainTitle(
          'BORANG PENGESAHAN BILANGAN PENGAWAL DAN REKOD KEHADIRAN PENGAWAL KESELAMATAN',
        ),
        _subTitle(
          'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
        ),
        _subTitle('DI BAWAH KEMENTERIAN PENDIDIKAN'),
        pw.SizedBox(height: 7),
        _centerLine('BULAN: ${months[month - 1]}     TAHUN: $year'),
        pw.SizedBox(height: 6),
        _metaRow(department),
        pw.SizedBox(height: 7),
        pw.Row(
          children: [
            pw.Expanded(
              child: _simpleTable(
                headers: const [
                  'Bilangan Pengawal Keselamatan Yang Ditetapkan Mengikut Syif Dalam Dokumen Perjanjian Kontrak',
                ],
                rows: [
                  ['Syif 1', 'Syif 2'],
                  ['$requiredShift1', '$requiredShift2'],
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              child: _simpleTable(
                headers: const ['Waktu Bertugas Setiap Syif'],
                rows: const [
                  ['Syif 1', 'Syif 2'],
                  [
                    'Jam 07:00 hingga\nJam 19:00',
                    'Jam 19:00 hingga\nJam 07:00',
                  ],
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        _pkk2Summary(blocks, actual, requiredShift1, requiredShift2),
        pw.Spacer(),
        _systemNote(),
        pw.SizedBox(height: 4),
        _sprmNotice(),
        pw.SizedBox(height: 5),
        _signatures(),
      ],
    );
  }

  static pw.Widget _pkk3Page({
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<int> guardIds,
    required Map<int, String> guardNames,
    required Map<int, String> guardStatus,
    required List<_GuardSession> sessions,
  }) {
    final dayCount = DateTime(year, month + 1, 0).day;
    final columns = <pw.TableRow>[];

    final top = <pw.Widget>[_greyCell('NAMA PK')];
    final status = <pw.Widget>[_greyCell('STATUS PK')];
    final hdr = <pw.Widget>[_greyCell('TARIKH')];
    for (var g = 0; g < 3; g++) {
      final id = g < guardIds.length ? guardIds[g] : null;
      top.add(_greyCell(id == null ? '' : guardNames[id]!, span: 7));
      status.add(
        _greyCell(id == null ? '' : guardStatus[id] ?? 'TETAP', span: 7),
      );
      hdr.addAll([
        _greyCell('SYIF'),
        _greyCell('MASUK'),
        _greyCell('KELUAR'),
        _greyCell('SYIF'),
        _greyCell('MASUK'),
        _greyCell('KELUAR'),
        _greyCell('CATATAN'),
      ]);
    }
    columns.add(pw.TableRow(children: top));
    columns.add(pw.TableRow(children: status));
    columns.add(pw.TableRow(children: hdr));

    for (var day = 1; day <= dayCount; day++) {
      final cells = <pw.Widget>[_tinyCell('$day')];
      for (var g = 0; g < 3; g++) {
        final id = g < guardIds.length ? guardIds[g] : null;
        final daySessions =
            id == null
                  ? <_GuardSession>[]
                  : sessions
                        .where(
                          (s) =>
                              s.userId == id &&
                              s.start.year == year &&
                              s.start.month == month &&
                              s.start.day == day,
                        )
                        .toList()
              ..sort((a, b) => a.start.compareTo(b.start));
        for (var s = 0; s < 2; s++) {
          final item = s < daySessions.length ? daySessions[s] : null;
          cells.add(_tinyCell(item == null ? '' : 'SYIF ${item.shift}'));
          cells.add(_tinyCell(item == null ? '' : _time(item.start)));
          cells.add(_tinyCell(item?.end == null ? '' : _time(item!.end!)));
        }
        cells.add(_tinyCell(''));
      }
      columns.add(pw.TableRow(children: cells));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _cornerLabel(
          'PKK 3 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2025 DAN SETERUSNYA)',
        ),
        _mainTitle(
          'BORANG PENGESAHAN KEHADIRAN PENGAWAL BERDASARKAN REKOD KEHADIRAN PENGAWAL KESELAMATAN',
        ),
        _subTitle(
          'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
        ),
        _subTitle('DI BAWAH KEMENTERIAN PENDIDIKAN'),
        pw.SizedBox(height: 5),
        _centerLine('BULAN: ${months[month - 1]}     TAHUN: $year'),
        pw.SizedBox(height: 5),
        _metaRow(department),
        pw.SizedBox(height: 5),
        pw.Table(
          border: pw.TableBorder.all(width: 0.45),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.55),
            for (var i = 1; i <= 21; i++) i: const pw.FlexColumnWidth(1),
          },
          children: columns,
        ),
        pw.Spacer(),
        _systemNote(),
        pw.SizedBox(height: 3),
        _sprmNotice(),
        pw.SizedBox(height: 4),
        _signatures(),
      ],
    );
  }

  static pw.Widget _pkk4Page({
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<_Pkk4Row> rows,
  }) {
    const slotHeaders = <String>[
      '0000 -\n0200',
      '0200 -\n0400',
      '0400 -\n0600',
      '0600 -\n0800',
      '0800 -\n1000',
      '1000 -\n1200',
      '1200 -\n1400',
      '1400 -\n1600',
      '1600 -\n1800',
      '1800 -\n2000',
      '2000 -\n2200',
      '2200 -\n2400',
    ];
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _greyCell('TARIKH'),
          _greyCell('GUARDTOUR POINT'),
          for (final h in slotHeaders) _greyCell(h),
          _greyCell('RUMUSAN'),
        ],
      ),
    ];
    for (final row in rows) {
      final complete = row.slots.where((value) => value.isNotEmpty).length;
      tableRows.add(
        pw.TableRow(
          children: [
            _tinyCell('${row.day}'),
            _tinyCell(row.checkpoint, align: pw.TextAlign.left),
            for (final value in row.slots) _tinyCell(value),
            _tinyCell('$complete/12'),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _cornerLabel(
          'PKK 4 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2025 DAN SETERUSNYA)',
        ),
        _mainTitle('BORANG PENGESAHAN PELAKSANAAN RONDAAN DAN CLOCKING'),
        _subTitle(
          'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
        ),
        _subTitle('DI BAWAH KEMENTERIAN PENDIDIKAN'),
        pw.SizedBox(height: 5),
        _centerLine('BULAN: ${months[month - 1]}     TAHUN: $year'),
        pw.SizedBox(height: 5),
        _metaRow(department),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            'LAPORAN SISTEM GUARD TOUR',
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Table(
          border: pw.TableBorder.all(width: 0.45),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(1.9),
            for (var i = 2; i <= 13; i++) i: const pw.FlexColumnWidth(1),
            14: const pw.FlexColumnWidth(1),
          },
          children: tableRows,
        ),
        pw.Spacer(),
        _systemNote(),
        pw.SizedBox(height: 3),
        _sprmNotice(),
        pw.SizedBox(height: 4),
        _signatures(),
      ],
    );
  }

  static pw.Widget _pkk2Summary(
    List<List<int>> blocks,
    Map<int, Map<int, Set<int>>> actual,
    int required1,
    int required2,
  ) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _greyCell(
            'Rumusan Bilangan Pengawal Keselamatan Mengikut Syif',
            span: 21,
          ),
        ],
      ),
    ];
    for (final block in blocks.take(3)) {
      final syif = <pw.Widget>[_greyCell('Syif')];
      final date = <pw.Widget>[_greyCell('Tarikh')];
      final count = <pw.Widget>[_greyCell('Bilangan PK')];
      for (var i = 0; i < 10; i++) {
        final day = i < block.length ? block[i] : null;
        syif.add(_tinyCell('Syif 1'));
        syif.add(_tinyCell('Syif 2'));
        date.add(_tinyCell(day == null ? '' : '$day', span: 2));
        final a1 = day == null
            ? ''
            : '${actual[day]?[1]?.length ?? 0}/$required1';
        final a2 = day == null
            ? ''
            : '${actual[day]?[2]?.length ?? 0}/$required2';
        count.add(_tinyCell(a1));
        count.add(_tinyCell(a2));
      }
      rows.add(pw.TableRow(children: syif));
      rows.add(pw.TableRow(children: date));
      rows.add(pw.TableRow(children: count));
    }
    return pw.Table(
      border: pw.TableBorder.all(width: 0.45),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.9),
        for (var i = 1; i <= 20; i++) i: const pw.FlexColumnWidth(1),
      },
      children: rows,
    );
  }

  static pw.Widget _simpleTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.45),
      children: [
        for (final header in headers)
          pw.TableRow(children: [_greyCell(header, span: 2)]),
        for (final row in rows)
          pw.TableRow(children: row.map((v) => _tinyCell(v)).toList()),
      ],
    );
  }

  static pw.Widget _metaRow(Map<String, dynamic> department) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: _field(
                'NAMA SYARIKAT:',
                '${department['companyName'] ?? ''}',
              ),
            ),
            pw.SizedBox(width: 40),
            pw.Expanded(child: _field('ZON:', '${department['zone'] ?? ''}')),
          ],
        ),
        pw.SizedBox(height: 4),
        _field('SEKOLAH/INSTITUSI PENDIDIKAN:', '${department['name'] ?? ''}'),
      ],
    );
  }

  static pw.Widget _field(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 6.4, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.45)),
            ),
            padding: const pw.EdgeInsets.only(left: 3, bottom: 1),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 6.4)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _cornerLabel(String text) => pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _mainTitle(String text) => pw.Center(
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _subTitle(String text) => pw.Center(
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 7.4, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _centerLine(String text) => pw.Center(
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _greyCell(String text, {int span = 1}) => pw.Container(
    alignment: pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    color: PdfColors.grey300,
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _tinyCell(
    String text, {
    int span = 1,
    pw.TextAlign align = pw.TextAlign.center,
  }) => pw.Container(
    alignment: align == pw.TextAlign.left
        ? pw.Alignment.centerLeft
        : pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 2.2),
    child: pw.Text(
      text,
      textAlign: align,
      style: const pw.TextStyle(fontSize: 5.2),
    ),
  );

  static pw.Widget _systemNote() => pw.Text(
    'Nota: Laporan sistem guard tour ini dijana secara digital. Sila pastikan segala maklumat yang dicetak adalah jelas dan sahih. Ruangan tandatangan penyedia, penyemak, dan Pengesah hendaklah dilengkapkan di setiap helaian.',
    style: const pw.TextStyle(fontSize: 5.1),
  );

  static pw.Widget _sprmNotice() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Peringatan:',
        style: pw.TextStyle(fontSize: 5.2, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Seksyen 18, Akta SPRM: Seseorang melakukan kesalahan jika dia memberi seseorang ejen, atau sebagai seorang ejen dia menggunakan, dengan niat hendak memperdayakan prinsipalnya, apa-apa resit, akaun atau dokumen lain yang berkenaan dengan prinsipalnya itu yang mengandungi pernyataan palsu, silap atau tidak lengkap tentang apa-apa butir matan.',
        style: const pw.TextStyle(fontSize: 4.5),
        textAlign: pw.TextAlign.justify,
      ),
    ],
  );

  static pw.Widget _signatures() {
    pw.Widget block(String heading, String role) => pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            heading,
            style: pw.TextStyle(fontSize: 5.3, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            '............................................................',
            style: const pw.TextStyle(fontSize: 5),
          ),
          pw.Text(
            '(Tandatangan & Cap Rasmi)',
            style: const pw.TextStyle(fontSize: 4.8),
          ),
          pw.Text(role, style: const pw.TextStyle(fontSize: 4.6)),
          pw.Text('Tarikh:', style: const pw.TextStyle(fontSize: 4.8)),
        ],
      ),
    );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        block('Disediakan Oleh:', 'Pengurus/Wakil Syarikat'),
        pw.SizedBox(width: 18),
        block(
          'Disemak Oleh:',
          'Institusi Pendidikan: Pegawai/Penolong Jurutera/Pegawai Eksekutif Kanan/Ketua Unit Khidmat Pengurusan/Sekolah: Guru Penolong Kanan Pentadbiran/Pegawai Pembangunan JPN atau Institusi Pendidikan atau PPD',
        ),
        pw.SizedBox(width: 18),
        block(
          'Disahkan Oleh:',
          'Institusi Pendidikan: Ketua/Timbalan Ketua Jabatan/Pengarah/Timbalan Pengarah JPN atau Institusi/PPD/Timbalan PPD/Ketua Sektor/Sekolah: Pengetua/Guru Besar',
        ),
      ],
    );
  }

  static Map<String, dynamic> _department(Map<String, dynamic> data) {
    final raw = data['department'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static List<_GuardSession> _attendanceSessions(List<dynamic> raw) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in raw) {
      final row = Map<String, dynamic>.from(item as Map);
      final jawatan = (row['jawatan'] ?? '').toString().toLowerCase();
      if (jawatan != 'patrol' && jawatan != 'supervisor') continue;
      final at = _malaysiaDateTime(row['punched_at']?.toString());
      if (at == null) continue;
      final userId = (row['user_id'] as num?)?.toInt() ?? 0;
      if (userId <= 0) continue;
      final dateKey = '${at.year}-${at.month}-${at.day}';
      grouped
          .putIfAbsent('$userId|$dateKey', () => <Map<String, dynamic>>[])
          .add({...row, '_local': at});
    }

    final result = <_GuardSession>[];
    for (final rows in grouped.values) {
      rows.sort(
        (a, b) => (a['_local'] as DateTime).compareTo(b['_local'] as DateTime),
      );
      final userId = (rows.first['user_id'] as num?)?.toInt() ?? 0;
      final name = (rows.first['nama'] ?? '-').toString();
      final ins = rows.where((r) => r['punch_type'] == 'IN').toList();
      for (var i = 0; i < ins.length; i++) {
        final start = ins[i]['_local'] as DateTime;
        DateTime? end;
        for (final row in rows) {
          final at = row['_local'] as DateTime;
          if (row['punch_type'] == 'OUT' && at.isAfter(start)) {
            end = at;
            break;
          }
        }
        final shift = start.hour >= 7 && start.hour < 19 ? 1 : 2;
        result.add(
          _GuardSession(
            userId: userId,
            name: name,
            start: start,
            end: end,
            shift: shift,
          ),
        );
      }
    }
    return result;
  }

  static DateTime? _malaysiaDateTime(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 8));
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _GuardSession {
  const _GuardSession({
    required this.userId,
    required this.name,
    required this.start,
    required this.end,
    required this.shift,
  });
  final int userId;
  final String name;
  final DateTime start;
  final DateTime? end;
  final int shift;
}

class _Pkk4Row {
  const _Pkk4Row({
    required this.day,
    required this.checkpoint,
    required this.slots,
  });
  final int day;
  final String checkpoint;
  final List<String> slots;
}
