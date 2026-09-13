from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Anchor not found in {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def insert_before(path: str, anchor: str, block: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if block.strip() in text:
        return
    if anchor not in text:
        raise RuntimeError(f'Anchor not found in {path}: {anchor!r}')
    p.write_text(text.replace(anchor, block + '\n' + anchor, 1), encoding='utf-8')


compiled_method = r'''  static Future<Uint8List> generateCompiled({
    required Map<String, dynamic> data,
    required int month,
    required int year,
  }) async {
    final department = _department(data);
    final attendanceSessions = _attendanceSessions(
      data['attendance'] as List<dynamic>? ?? const [],
    );
    final guards = _guards(data, attendanceSessions);
    final guardPages = guards.isEmpty
        ? const <List<_GuardMeta>>[<_GuardMeta>[]]
        : <List<_GuardMeta>>[
            for (var start = 0; start < guards.length; start += 4)
              guards.skip(start).take(4).toList(),
          ];
    final requiredByShift = _requiredGuardsByShift(attendanceSessions, month, year);

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

    final pkk4Rows = <_Pkk4Row>[];
    final activeDays =
        scans.map((row) => (row['_local'] as DateTime).day).toSet().toList()
          ..sort();
    for (final day in activeDays) {
      for (var checkpointIndex = 0;
          checkpointIndex < checkpoints.length;
          checkpointIndex++) {
        final checkpoint = checkpoints[checkpointIndex];
        final checkpointId = (checkpoint['id'] as num?)?.toInt() ?? 0;
        final slots = List<String>.filled(12, '');
        for (var slot = 0; slot < 12; slot++) {
          DateTime? earliest;
          for (final scan in scans) {
            if ((scan['checkpoint_id'] as num?)?.toInt() != checkpointId) continue;
            final at = scan['_local'] as DateTime;
            if (at.day != day || (at.hour ~/ 2) != slot) continue;
            if (earliest == null || at.isBefore(earliest)) earliest = at;
          }
          if (earliest != null) slots[slot] = _hhmm(earliest);
        }
        pkk4Rows.add(
          _Pkk4Row(
            day: day,
            showDate: checkpointIndex == 0,
            checkpoint: (checkpoint['name'] ?? 'Checkpoint').toString(),
            slots: slots,
          ),
        );
      }
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 52, 42, 48),
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Spacer(),
            pw.Center(
              child: pw.Text(
                '${department['companyName'] ?? ''}'.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 42),
            pw.Center(
              child: pw.Text(
                'LAPORAN PERKHIDMATAN\nKAWALAN KESELAMATAN',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text(
                'BULAN ${months[month - 1]} $year',
                style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 42),
            pw.Center(
              child: pw.Text(
                '${department['name'] ?? ''}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if ('${department['zone'] ?? ''}'.trim().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Text('ZON: ${department['zone']}')),
            ],
            pw.Spacer(),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.7),
              ),
              child: pw.Text(
                'Dokumen ini dijana daripada rekod sebenar ZPatrol. Kandungan pakej: PKK 2, PKK 3 dan PKK 4.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );

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
            sessions: attendanceSessions,
            requiredShift1: requiredByShift[1] ?? 0,
            requiredShift2: requiredByShift[2] ?? 0,
          ),
        ),
      );
    }

    final effectiveGuards = guards.isEmpty
        ? const <_GuardMeta>[_GuardMeta(id: 0, name: '-', noPk: '')]
        : guards;
    for (final guard in effectiveGuards) {
      final guardSessions = attendanceSessions
          .where((item) =>
              item.userId == guard.id &&
              item.start.year == year &&
              item.start.month == month)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      const rowsPerPage = 20;
      final pageCount = math.max(1, (guardSessions.length / rowsPerPage).ceil());
      for (var page = 0; page < pageCount; page++) {
        final pageRows = guardSessions.skip(page * rowsPerPage).take(rowsPerPage).toList();
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

    final pkk4Pages = _splitPkk4Rows(pkk4Rows);
    for (var page = 0; page < pkk4Pages.length; page++) {
      final isFirst = page == 0;
      final isContinuation = page > 0;
      final isSinglePage = pkk4Pages.length == 1;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 18),
          build: (_) => _pkk4Page(
            department: department,
            month: month,
            year: year,
            rows: pkk4Pages[page],
            showDocumentHeader: isFirst,
            showSignatureArea: isSinglePage || isContinuation,
          ),
        ),
      );
    }
    return doc.save();
  }
'''

insert_before(
    'lib/features/admin/pkk_pdf_generator.dart',
    '  static Future<Uint8List> generatePkk2({',
    compiled_method,
)

replace_once(
    'lib/features/admin/report_screen.dart',
    """      final Uint8List bytes = switch (type) {\n        _PkkType.pkk2 => await PkkPdfGenerator.generatePkk2(\n""",
    """      final Uint8List bytes = switch (type) {\n        _PkkType.compiled => await PkkPdfGenerator.generateCompiled(\n          data: data,\n          month: _month,\n          year: _year,\n        ),\n        _PkkType.pkk2 => await PkkPdfGenerator.generatePkk2(\n""",
)

replace_once(
    'lib/features/admin/report_screen.dart',
    """                  _ReportButton(\n                    icon: Icons.groups_rounded,\n                    title: 'Jana PKK 2 (PDF)',\n""",
    """                  _ReportButton(\n                    icon: Icons.library_books_rounded,\n                    title: 'Jana Pakej PKK Lengkap (PDF)',\n                    subtitle: 'Muka hadapan + PKK 2 + PKK 3 + PKK 4 dalam satu dokumen',\n                    enabled: !_generating && !_loadingDepartments && _departmentId != null,\n                    onPressed: () => _generate(_PkkType.compiled),\n                  ),\n                  const SizedBox(height: 10),\n                  _ReportButton(\n                    icon: Icons.groups_rounded,\n                    title: 'Jana PKK 2 (PDF)',\n""",
)

replace_once(
    'lib/features/admin/report_screen.dart',
    """enum _PkkType {\n  pkk2('PKK 2', 'PKK_2'),\n""",
    """enum _PkkType {\n  compiled('Pakej PKK Lengkap', 'PKK_LENGKAP'),\n  pkk2('PKK 2', 'PKK_2'),\n""",
)

print('Applied compiled PKK report improvements.')
