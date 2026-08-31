import 'dart:typed_data';

import 'package:excel/excel.dart';

class PkkExcelGenerator {
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

  static Uint8List generatePkk2({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) {
    final department = _department(data);
    final sessions = _attendanceSessions(
      data['attendance'] as List<dynamic>? ?? const [],
    );
    final days = DateTime(year, month + 1, 0).day;

    final actual = <int, Map<int, Set<int>>>{};
    for (final session in sessions) {
      if (session.start.year != year || session.start.month != month) continue;
      final byShift = actual.putIfAbsent(
        session.start.day,
        () => <int, Set<int>>{},
      );
      byShift.putIfAbsent(session.shift, () => <int>{}).add(session.userId);
    }

    var requiredShift1 = 0;
    var requiredShift2 = 0;
    for (final row in actual.values) {
      requiredShift1 = _max(requiredShift1, row[1]?.length ?? 0);
      requiredShift2 = _max(requiredShift2, row[2]?.length ?? 0);
    }

    final excel = Excel.createExcel();
    final firstName = 'PKK 2';
    excel.rename('Sheet1', firstName);
    _buildPkk2Page(
      excel[firstName],
      department: department,
      month: month,
      year: year,
      pageDays: List<int>.generate(_min(days, 30), (index) => index + 1),
      actual: actual,
      requiredShift1: requiredShift1,
      requiredShift2: requiredShift2,
    );

    if (days == 31) {
      final page2 = excel['PKK 2 - Muka 2'];
      _buildPkk2Page(
        page2,
        department: department,
        month: month,
        year: year,
        pageDays: const [31],
        actual: actual,
        requiredShift1: requiredShift1,
        requiredShift2: requiredShift2,
      );
    }
    excel.setDefaultSheet(firstName);
    return Uint8List.fromList(excel.save() ?? const <int>[]);
  }

  static Uint8List generatePkk3({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) {
    final department = _department(data);
    final sessions = _attendanceSessions(
      data['attendance'] as List<dynamic>? ?? const [],
    );
    final guardNames = <int, String>{};
    for (final item in data['attendance'] as List<dynamic>? ?? const []) {
      final row = Map<String, dynamic>.from(item as Map);
      final jawatan = (row['jawatan'] ?? '').toString().toLowerCase();
      if (jawatan != 'patrol' && jawatan != 'supervisor') continue;
      final userId = (row['user_id'] as num?)?.toInt() ?? 0;
      if (userId > 0) guardNames[userId] = (row['nama'] ?? '-').toString();
    }
    for (final session in sessions) {
      if (session.start.year == year && session.start.month == month) {
        guardNames.putIfAbsent(session.userId, () => session.name);
      }
    }

    final guardIds = guardNames.keys.toList()
      ..sort((a, b) => guardNames[a]!.compareTo(guardNames[b]!));
    final pages = guardIds.isEmpty ? 1 : ((guardIds.length + 2) ~/ 3);
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'PKK 3');

    for (var page = 0; page < pages; page++) {
      final sheetName = page == 0 ? 'PKK 3' : 'PKK 3 - Muka ${page + 1}';
      final sheet = excel[sheetName];
      final pageGuardIds = guardIds.skip(page * 3).take(3).toList();
      _buildPkk3Page(
        sheet,
        department: department,
        month: month,
        year: year,
        guardIds: pageGuardIds,
        guardNames: guardNames,
        sessions: sessions,
      );
    }
    excel.setDefaultSheet('PKK 3');
    return Uint8List.fromList(excel.save() ?? const <int>[]);
  }

  static Uint8List generatePkk4({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) {
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
      checkpoints.add(Map<String, dynamic>.from(item as Map));
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

    final pageCount = rows.isEmpty ? 1 : ((rows.length + 59) ~/ 60);
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'PKK 4');
    for (var page = 0; page < pageCount; page++) {
      final name = page == 0 ? 'PKK 4' : 'PKK 4 - Muka ${page + 1}';
      _buildPkk4Page(
        excel[name],
        department: department,
        month: month,
        year: year,
        rows: rows.skip(page * 60).take(60).toList(),
      );
    }
    excel.setDefaultSheet('PKK 4');
    return Uint8List.fromList(excel.save() ?? const <int>[]);
  }

  static void _buildPkk2Page(
    Sheet sheet, {
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<int> pageDays,
    required Map<int, Map<int, Set<int>>> actual,
    required int requiredShift1,
    required int requiredShift2,
  }) {
    _pkk2Dimensions(sheet);
    _text(
      sheet,
      'W1',
      'PKK 2 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2025 DAN SETERUSNYA)',
      style: _smallBoldRight,
    );
    _mergeText(
      sheet,
      'A3',
      'W3',
      'BORANG PENGESAHAN BILANGAN PENGAWAL DAN REKOD KEHADIRAN PENGAWAL KESELAMATAN',
      _title,
    );
    _mergeText(
      sheet,
      'A4',
      'W4',
      'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
      _title,
    );
    _mergeText(sheet, 'A5', 'W5', 'DI BAWAH KEMENTERIAN PENDIDIKAN', _title);
    _mergeText(
      sheet,
      'A7',
      'U7',
      'BULAN: ${months[month - 1]}     TAHUN: $year',
      _centerBold,
    );
    _text(sheet, 'A9', 'NAMA SYARIKAT:', style: _bold);
    _text(sheet, 'B9', (department['companyName'] ?? '').toString());
    _text(sheet, 'P9', 'ZON:', style: _bold);
    _text(sheet, 'Q9', (department['zone'] ?? '').toString());
    _text(sheet, 'A11', 'SEKOLAH/\nINSTITUSI\nPENDIDIKAN:', style: _boldWrap);
    _text(sheet, 'C11', (department['name'] ?? '').toString());

    _mergeText(
      sheet,
      'A16',
      'J16',
      'Bilangan Pengawal Keselamatan Yang Ditetapkan Mengikut Syif Dalam Dokumen Perjanjian Kontrak',
      _header,
    );
    _mergeText(sheet, 'L16', 'V16', 'Waktu Bertugas Setiap Syif', _header);
    _mergeText(sheet, 'A17', 'D17', 'Syif 1', _tableCenter);
    _mergeText(sheet, 'E17', 'J17', 'Syif 2', _tableCenter);
    _mergeText(sheet, 'L17', 'P17', 'Syif 1', _tableCenter);
    _mergeText(sheet, 'Q17', 'V17', 'Syif 2', _tableCenter);
    _mergeText(sheet, 'A18', 'D18', '$requiredShift1', _tableCenter);
    _mergeText(sheet, 'E18', 'J18', '$requiredShift2', _tableCenter);
    _mergeText(
      sheet,
      'L18',
      'P18',
      'Jam 07:00 hingga\nJam 19:00',
      _tableCenter,
    );
    _mergeText(
      sheet,
      'Q18',
      'V18',
      'Jam 19:00 hingga\nJam 07:00',
      _tableCenter,
    );

    _mergeText(
      sheet,
      'A21',
      'V21',
      'Rumusan Bilangan Pengawal Keselamatan Mengikut Syif',
      _header,
    );
    final blocks = <(int, int, int)>[(22, 23, 24), (25, 26, 27), (28, 29, 30)];
    var dayCursor = 0;
    for (final block in blocks) {
      final syifRow = block.$1;
      final dateRow = block.$2;
      final countRow = block.$3;
      _mergeText(sheet, 'A$syifRow', 'B$syifRow', 'Syif', _tableHeader);
      _mergeText(sheet, 'A$dateRow', 'B$dateRow', 'Tarikh', _tableHeader);
      _mergeText(
        sheet,
        'A$countRow',
        'B$countRow',
        'Bilangan PK',
        _tableHeader,
      );
      for (var slot = 0; slot < 10; slot++) {
        final c1 = 2 + slot * 2;
        final c2 = c1 + 1;
        _textAt(sheet, c1, syifRow - 1, 'Syif 1', style: _tableCenter);
        _textAt(sheet, c2, syifRow - 1, 'Syif 2', style: _tableCenter);
        _mergeByIndex(sheet, c1, dateRow - 1, c2, dateRow - 1);
        final day = dayCursor < pageDays.length ? pageDays[dayCursor] : null;
        _textAt(
          sheet,
          c1,
          dateRow - 1,
          day == null ? '' : '$day',
          style: _tableCenter,
        );
        final a1 = day == null ? 0 : actual[day]?[1]?.length ?? 0;
        final a2 = day == null ? 0 : actual[day]?[2]?.length ?? 0;
        _textAt(
          sheet,
          c1,
          countRow - 1,
          day == null ? '' : '$a1/$requiredShift1',
          style: _tableCenter,
        );
        _textAt(
          sheet,
          c2,
          countRow - 1,
          day == null ? '' : '$a2/$requiredShift2',
          style: _tableCenter,
        );
        dayCursor++;
      }
    }
    _signatureAndNoticePkk2(sheet);
  }

  static void _buildPkk3Page(
    Sheet sheet, {
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<int> guardIds,
    required Map<int, String> guardNames,
    required List<_GuardSession> sessions,
  }) {
    _pkk3Dimensions(sheet);
    _text(
      sheet,
      'W1',
      'PKK 3 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2025 DAN SETERUSNYA)',
      style: _smallBoldRight,
    );
    _mergeText(
      sheet,
      'A3',
      'V3',
      'BORANG PENGESAHAN KEHADIRAN PENGAWAL BERDASARKAN REKOD KEHADIRAN PENGAWAL KESELAMATAN',
      _title,
    );
    _mergeText(
      sheet,
      'A4',
      'V4',
      'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
      _title,
    );
    _mergeText(sheet, 'A5', 'V5', 'DI BAWAH KEMENTERIAN PENDIDIKAN', _title);
    _mergeText(
      sheet,
      'A7',
      'U7',
      'BULAN: ${months[month - 1]}     TAHUN: $year',
      _centerBold,
    );
    _text(sheet, 'A9', 'NAMA SYARIKAT:', style: _bold);
    _text(sheet, 'B9', (department['companyName'] ?? '').toString());
    _text(sheet, 'P9', 'ZON:', style: _bold);
    _text(sheet, 'Q9', (department['zone'] ?? '').toString());
    _text(sheet, 'A11', 'SEKOLAH/\nINSTITUSI\nPENDIDIKAN:', style: _boldWrap);
    _text(sheet, 'C11', (department['name'] ?? '').toString());

    _text(sheet, 'A14', 'NAMA PK', style: _tableHeader);
    _text(sheet, 'A15', 'STATUS PK', style: _tableHeader);
    _text(sheet, 'A16', 'TARIKH', style: _tableHeader);
    final starts = [1, 8, 15];
    for (var g = 0; g < 3; g++) {
      final start = starts[g];
      final end = start + 6;
      _mergeByIndex(sheet, start, 13, end, 13);
      _mergeByIndex(sheet, start, 14, end, 14);
      final id = g < guardIds.length ? guardIds[g] : null;
      _textAt(
        sheet,
        start,
        13,
        id == null ? '' : guardNames[id] ?? '',
        style: _header,
      );
      _textAt(sheet, start, 14, '', style: _header);
      const labels = [
        'SYIF',
        'MASUK',
        'KELUAR',
        'SYIF',
        'MASUK',
        'KELUAR',
        'CATATAN',
      ];
      for (var i = 0; i < 7; i++) {
        _textAt(sheet, start + i, 15, labels[i], style: _tableHeader);
      }
    }

    final days = DateTime(year, month + 1, 0).day;
    final byGuardDay = <int, Map<int, Map<int, _GuardSession>>>{};
    for (final session in sessions) {
      if (session.start.year != year || session.start.month != month) continue;
      byGuardDay
              .putIfAbsent(
                session.userId,
                () => <int, Map<int, _GuardSession>>{},
              )
              .putIfAbsent(
                session.start.day,
                () => <int, _GuardSession>{},
              )[session.shift] =
          session;
    }

    for (var rowIndex = 17; rowIndex <= 65; rowIndex++) {
      for (var col = 0; col < 22; col++) {
        _textAt(sheet, col, rowIndex, '', style: _tableBody);
      }
    }
    for (var day = 1; day <= days; day++) {
      final row = 17 + (day - 1);
      _textAt(
        sheet,
        0,
        row,
        '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year',
        style: _tableCenter,
      );
      for (var g = 0; g < guardIds.length; g++) {
        final start = starts[g];
        final map =
            byGuardDay[guardIds[g]]?[day] ?? const <int, _GuardSession>{};
        final s1 = map[1];
        final s2 = map[2];
        _textAt(
          sheet,
          start,
          row,
          s1 == null ? '' : 'SYIF 1',
          style: _tableCenter,
        );
        _textAt(
          sheet,
          start + 1,
          row,
          s1 == null ? '' : _time(s1.start),
          style: _tableCenter,
        );
        _textAt(
          sheet,
          start + 2,
          row,
          s1?.end == null ? '' : _time(s1!.end!),
          style: _tableCenter,
        );
        _textAt(
          sheet,
          start + 3,
          row,
          s2 == null ? '' : 'SYIF 2',
          style: _tableCenter,
        );
        _textAt(
          sheet,
          start + 4,
          row,
          s2 == null ? '' : _time(s2.start),
          style: _tableCenter,
        );
        _textAt(
          sheet,
          start + 5,
          row,
          s2?.end == null ? '' : _time(s2!.end!),
          style: _tableCenter,
        );
        _textAt(sheet, start + 6, row, '', style: _tableBody);
      }
    }
    _signatureAndNoticePkk3(sheet);
  }

  static void _buildPkk4Page(
    Sheet sheet, {
    required Map<String, dynamic> department,
    required int month,
    required int year,
    required List<_Pkk4Row> rows,
  }) {
    _pkk4Dimensions(sheet);
    _text(
      sheet,
      'O1',
      'PKK 4 (BAGI KONTRAK YANG BERMULA PADA 1 OKTOBER 2025 DAN SETERUSNYA)',
      style: _smallBoldRight,
    );
    _mergeText(
      sheet,
      'A3',
      'O3',
      'BORANG PENGESAHAN PELAKSANAAN RONDAAN DAN CLOCKING',
      _title,
    );
    _mergeText(
      sheet,
      'A4',
      'O4',
      'PERKHIDMATAN KAWALAN KESELAMATAN DI SEKOLAH/INSTITUSI PENDIDIKAN',
      _title,
    );
    _mergeText(sheet, 'A5', 'O5', 'DI BAWAH KEMENTERIAN PENDIDIKAN', _title);
    _mergeText(
      sheet,
      'A7',
      'O7',
      'BULAN: ${months[month - 1]}     TAHUN: $year',
      _centerBold,
    );
    _text(sheet, 'A9', 'NAMA SYARIKAT:', style: _bold);
    _text(sheet, 'B9', (department['companyName'] ?? '').toString());
    _text(sheet, 'J9', 'ZON:', style: _bold);
    _text(sheet, 'K9', (department['zone'] ?? '').toString());
    _text(sheet, 'A11', 'SEKOLAH/INSTITUSI PENDIDIKAN:', style: _bold);
    _text(sheet, 'C11', (department['name'] ?? '').toString());

    _mergeText(sheet, 'A14', 'A16', 'TARIKH', _header);
    _mergeText(sheet, 'B14', 'B16', 'GUARDTOUR POINT', _header);
    _mergeText(sheet, 'C14', 'N14', 'LAPORAN SISTEM GUARD TOUR', _header);
    _mergeText(sheet, 'O14', 'O16', 'RUMUSAN', _header);
    const starts = [
      '0000 -',
      '0200 -',
      '0400 -',
      '0600 -',
      '0800 -',
      '1000 -',
      '1200 -',
      '1400 -',
      '1600 -',
      '1800 -',
      '2000 -',
      '2200 -',
    ];
    const ends = [
      '0200',
      '0400',
      '0600',
      '0800',
      '1000',
      '1200',
      '1400',
      '1600',
      '1800',
      '2000',
      '2200',
      '2400',
    ];
    for (var i = 0; i < 12; i++) {
      _textAt(sheet, 2 + i, 14, starts[i], style: _tableHeader);
      _textAt(sheet, 2 + i, 15, ends[i], style: _tableHeader);
    }

    for (var r = 17; r <= 76; r++) {
      for (var c = 0; c < 15; c++) {
        _textAt(sheet, c, r, '', style: _tableBody);
      }
    }
    int? previousDay;
    for (var i = 0; i < rows.length; i++) {
      final target = 17 + i;
      final row = rows[i];
      _textAt(
        sheet,
        0,
        target,
        previousDay == row.day
            ? ''
            : '${row.day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year',
        style: _tableCenter,
      );
      previousDay = row.day;
      _textAt(sheet, 1, target, row.checkpoint, style: _tableBody);
      var complete = 0;
      for (var slot = 0; slot < 12; slot++) {
        final value = row.slots[slot];
        if (value.isNotEmpty) complete++;
        _textAt(sheet, 2 + slot, target, value, style: _tableCenter);
      }
      _textAt(sheet, 14, target, '$complete/12', style: _tableCenter);
    }
    _signatureAndNoticePkk4(sheet);
  }

  static void _signatureAndNoticePkk2(Sheet sheet) {
    _mergeText(
      sheet,
      'A32',
      'U33',
      'Nota: \nLaporan sistem guard tour ini dijana secara digital. Sila pastikan segala maklumat yang dicetak adalah jelas dan sahih. Ruangan tandatangan penyedia, penyemak, dan Pengesah hendaklah dilengkapkan di setiap helaian.',
      _note,
    );
    _text(sheet, 'A35', 'Peringatan:', style: _bold);
    _mergeText(sheet, 'A36', 'U36', _sprm, _note);
    _signatureBlock(
      sheet,
      prepared: 'A38',
      checked: 'F38',
      approved: 'P38',
      lineRow: 41,
      roleRow: 43,
      dateRow: 44,
    );
  }

  static void _signatureAndNoticePkk3(Sheet sheet) {
    _mergeText(
      sheet,
      'A70',
      'U71',
      'Nota: \nLaporan sistem guard tour ini dijana secara digital. Sila pastikan segala maklumat yang dicetak adalah jelas dan sahih. Ruangan tandatangan penyedia, penyemak, dan Pengesah hendaklah dilengkapkan di setiap helaian.',
      _note,
    );
    _text(sheet, 'A73', 'Peringatan:', style: _bold);
    _mergeText(sheet, 'A74', 'U74', _sprm, _note);
    _signatureBlock(
      sheet,
      prepared: 'A76',
      checked: 'F76',
      approved: 'P76',
      lineRow: 79,
      roleRow: 81,
      dateRow: 82,
    );
  }

  static void _signatureAndNoticePkk4(Sheet sheet) {
    _mergeText(
      sheet,
      'A78',
      'O78',
      'Nota: \nLaporan sistem guard tour ini dijana secara digital. Sila pastikan segala maklumat yang dicetak adalah jelas dan sahih. Ruangan tandatangan penyedia, penyemak, dan Pengesah hendaklah dilengkapkan di setiap helaian.',
      _note,
    );
    _text(sheet, 'A80', 'Peringatan:', style: _bold);
    _mergeText(sheet, 'A81', 'O81', _sprm, _note);
    _signatureBlock(
      sheet,
      prepared: 'A83',
      checked: 'C83',
      approved: 'J83',
      lineRow: 90,
      roleRow: 92,
      dateRow: 93,
    );
  }

  static void _signatureBlock(
    Sheet sheet, {
    required String prepared,
    required String checked,
    required String approved,
    required int lineRow,
    required int roleRow,
    required int dateRow,
  }) {
    _text(sheet, prepared, 'Disediakan Oleh:', style: _bold);
    _text(sheet, checked, 'Disemak Oleh:', style: _bold);
    _text(sheet, approved, 'Disahkan Oleh:', style: _bold);
    final pCol = CellIndex.indexByString(prepared).columnIndex;
    final cCol = CellIndex.indexByString(checked).columnIndex;
    final aCol = CellIndex.indexByString(approved).columnIndex;
    _textAt(sheet, pCol, lineRow - 1, '……………………………...……………………..');
    _textAt(sheet, cCol, lineRow - 1, '…………..………...……..…….');
    _textAt(sheet, aCol, lineRow - 1, '…………………..…………...…..….');
    _textAt(sheet, pCol, lineRow, '(Tandatangan & Cap Rasmi)');
    _textAt(sheet, cCol, lineRow, '(Tandatangan & Cap Rasmi)');
    _textAt(sheet, aCol, lineRow, '(Tandatangan & Cap Rasmi)');
    _textAt(sheet, pCol, roleRow - 1, 'Pengurus/Wakil Syarikat');
    _textAt(
      sheet,
      cCol,
      roleRow - 1,
      'Institusi Pendidikan: Pegawai/Penolong Jurutera/Pegawai Eksekutif Kanan/',
    );
    _textAt(sheet, cCol, roleRow, 'Ketua Unit Khidmat Pengurusan');
    _textAt(
      sheet,
      cCol,
      roleRow + 1,
      'Sekolah: Guru Penolong Kanan Pentadbiran',
    );
    _textAt(
      sheet,
      cCol,
      roleRow + 2,
      'Pusat Kokurikulum: Pegawai/Penyelia Pusat Kokurikulum',
    );
    _textAt(
      sheet,
      cCol,
      roleRow + 3,
      'Pegawai Pembangunan JPN atau Institusi Pendidikan atau PPD',
    );
    _textAt(
      sheet,
      aCol,
      roleRow - 1,
      'Institusi Pendidikan: Ketua/Timbalan Ketua Jabatan/',
    );
    _textAt(
      sheet,
      aCol,
      roleRow,
      'Pengarah/Timbalan Pengarah JPN atau Institusi/',
    );
    _textAt(
      sheet,
      aCol,
      roleRow + 1,
      'Pegawai Pendidikan Daerah (PPD)/Timbalan PPD/Ketua Sektor',
    );
    _textAt(sheet, aCol, roleRow + 2, 'Sekolah: Pengetua/Guru Besar');
    _textAt(
      sheet,
      aCol,
      roleRow + 3,
      'Pusat Kokurikulum: Ketua Unit Pusat Kokurikulum',
    );
    _textAt(
      sheet,
      aCol,
      roleRow + 4,
      'Timbalan Pengarah JPN atau Institusi/PPD/Timbalan PPD/Ketua Sektor',
    );
    _textAt(sheet, pCol, dateRow - 1, 'Tarikh:');
    _textAt(sheet, cCol, roleRow + 4, 'Tarikh:');
    _textAt(sheet, aCol, roleRow + 5, 'Tarikh:');
  }

  static Map<String, dynamic> _department(Map<String, dynamic> data) {
    final raw = data['department'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static List<_GuardSession> _attendanceSessions(List<dynamic> raw) {
    final byUser = <int, List<Map<String, dynamic>>>{};
    for (final item in raw) {
      final row = Map<String, dynamic>.from(item as Map);
      final jawatan = (row['jawatan'] ?? '').toString().toLowerCase();
      if (jawatan != 'patrol' && jawatan != 'supervisor') continue;
      final userId = (row['user_id'] as num?)?.toInt() ?? 0;
      if (userId <= 0) continue;
      final at = _malaysiaDateTime(row['punched_at']?.toString());
      if (at == null) continue;
      row['_local'] = at;
      byUser.putIfAbsent(userId, () => <Map<String, dynamic>>[]).add(row);
    }
    final result = <_GuardSession>[];
    for (final entry in byUser.entries) {
      final rows = entry.value
        ..sort(
          (a, b) =>
              (a['_local'] as DateTime).compareTo(b['_local'] as DateTime),
        );
      Map<String, dynamic>? pending;
      for (final row in rows) {
        final type = (row['punch_type'] ?? '').toString().toUpperCase();
        if (type == 'IN') {
          if (pending != null) {
            result.add(_sessionFrom(pending, null));
          }
          pending = row;
        } else if (type == 'OUT' && pending != null) {
          final start = pending['_local'] as DateTime;
          final end = row['_local'] as DateTime;
          if (end.difference(start).inHours <= 20) {
            result.add(_sessionFrom(pending, row));
            pending = null;
          }
        }
      }
      if (pending != null) result.add(_sessionFrom(pending, null));
    }
    return result;
  }

  static _GuardSession _sessionFrom(
    Map<String, dynamic> startRow,
    Map<String, dynamic>? endRow,
  ) {
    final start = startRow['_local'] as DateTime;
    return _GuardSession(
      userId: (startRow['user_id'] as num?)?.toInt() ?? 0,
      name: (startRow['nama'] ?? '-').toString(),
      start: start,
      end: endRow?['_local'] as DateTime?,
      shift: start.hour >= 7 && start.hour < 19 ? 1 : 2,
    );
  }

  static DateTime? _malaysiaDateTime(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 8));
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static void _pkk2Dimensions(Sheet sheet) {
    final widths = <int, double>{
      0: 22.36328125,
      1: 11.08984375,
      for (var c = 2; c <= 21; c++) c: 12.81640625,
      22: 11.90625,
    };
    widths.forEach(sheet.setColumnWidth);
    for (var r = 0; r < 56; r++) {
      sheet.setRowHeight(r, 20.15);
    }
    for (final r in [20, 21, 22, 23, 24, 25, 26, 27, 28, 29]) {
      sheet.setRowHeight(r, 42);
    }
    sheet.setRowHeight(35, 100.5);
  }

  static void _pkk3Dimensions(Sheet sheet) {
    sheet.setColumnWidth(0, 22.36328125);
    for (var c = 1; c <= 2; c++) {
      sheet.setColumnWidth(c, 11.08984375);
    }
    for (var c = 3; c <= 22; c++) {
      sheet.setColumnWidth(c, 11.90625);
    }
    for (var r = 0; r < 94; r++) {
      sheet.setRowHeight(r, 18);
    }
    for (final r in [13, 14, 15]) {
      sheet.setRowHeight(r, 24.5);
    }
    sheet.setRowHeight(73, 69);
  }

  static void _pkk4Dimensions(Sheet sheet) {
    sheet.setColumnWidth(0, 27.453125);
    sheet.setColumnWidth(1, 28);
    for (var c = 2; c <= 14; c++) {
      sheet.setColumnWidth(c, 14.453125);
    }
    for (var r = 0; r < 105; r++) {
      sheet.setRowHeight(r, 18);
    }
    sheet.setRowHeight(77, 46.5);
    sheet.setRowHeight(80, 50.15);
  }

  static final _thin = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.black,
  );
  static final _base = CellStyle(
    fontFamily: 'Arial',
    fontSize: 8,
    verticalAlign: VerticalAlign.Center,
  );
  static final _bold = _base.copyWith(boldVal: true);
  static final _boldWrap = _base.copyWith(
    boldVal: true,
    textWrappingVal: TextWrapping.WrapText,
  );
  static final _title = _base.copyWith(
    boldVal: true,
    fontSizeVal: 9,
    horizontalAlignVal: HorizontalAlign.Center,
    verticalAlignVal: VerticalAlign.Center,
  );
  static final _centerBold = _base.copyWith(
    boldVal: true,
    horizontalAlignVal: HorizontalAlign.Center,
  );
  static final _smallBoldRight = _base.copyWith(
    boldVal: true,
    fontSizeVal: 7,
    horizontalAlignVal: HorizontalAlign.Right,
  );
  static final _header = _base.copyWith(
    boldVal: true,
    horizontalAlignVal: HorizontalAlign.Center,
    verticalAlignVal: VerticalAlign.Center,
    textWrappingVal: TextWrapping.WrapText,
    backgroundColorHexVal: ExcelColor.fromHexString('#D9D9D9'),
    leftBorderVal: _thin,
    rightBorderVal: _thin,
    topBorderVal: _thin,
    bottomBorderVal: _thin,
  );
  static final _tableHeader = _header.copyWith(fontSizeVal: 8);
  static final _tableBody = _base.copyWith(
    leftBorderVal: _thin,
    rightBorderVal: _thin,
    topBorderVal: _thin,
    bottomBorderVal: _thin,
    textWrappingVal: TextWrapping.WrapText,
  );
  static final _tableCenter = _tableBody.copyWith(
    horizontalAlignVal: HorizontalAlign.Center,
    verticalAlignVal: VerticalAlign.Center,
  );
  static final _note = _base.copyWith(
    fontSizeVal: 7,
    textWrappingVal: TextWrapping.WrapText,
    verticalAlignVal: VerticalAlign.Top,
  );

  static const _sprm =
      'Seksyen 18, Akta SPRM: "Seseorang melakukan kesalahan jika dia memberi seseorang ejen, atau sebagai seorang ejen dia menggunakan, dengan niat hendak memperdayakan prinsipalnya, apa-apa resit, akaun atau dokumen lain yang berkenaan dengan prinsipalnya itu mempunyai kepentingan, dan yang dia mempunyai sebab untuk mempercayai mengandungi apa-apa pernyataan yang palsu atau silap atau tidak lengkap tentang apa-apa butir matan, dan yang dimaksudkan untuk mengelirukan prinsipalnya."';

  static void _text(Sheet sheet, String ref, String value, {CellStyle? style}) {
    final cell = sheet.cell(CellIndex.indexByString(ref));
    cell.value = TextCellValue(value);
    cell.cellStyle = style ?? _base;
  }

  static void _textAt(
    Sheet sheet,
    int col,
    int row,
    String value, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = TextCellValue(value);
    cell.cellStyle = style ?? _base;
  }

  static void _mergeText(
    Sheet sheet,
    String start,
    String end,
    String value,
    CellStyle style,
  ) {
    sheet.merge(
      CellIndex.indexByString(start),
      CellIndex.indexByString(end),
      customValue: TextCellValue(value),
    );
    sheet.setMergedCellStyle(CellIndex.indexByString(start), style);
  }

  static void _mergeByIndex(
    Sheet sheet,
    int startCol,
    int startRow,
    int endCol,
    int endRow,
  ) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: startRow),
      CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: endRow),
    );
  }

  static int _max(int a, int b) => a > b ? a : b;
  static int _min(int a, int b) => a < b ? a : b;
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
