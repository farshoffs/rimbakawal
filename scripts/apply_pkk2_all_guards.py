from pathlib import Path

path = Path('lib/features/admin/pkk_pdf_generator.dart')
text = path.read_text(encoding='utf-8')

old_guard_pages = """    final guardPages = guards.isEmpty
        ? const <List<_GuardMeta>>[<_GuardMeta>[]]
        : <List<_GuardMeta>>[
            for (var start = 0; start < guards.length; start += 4)
              guards.skip(start).take(4).toList(),
          ];
"""
count = text.count(old_guard_pages)
if count != 2:
    raise SystemExit(f'Expected 2 guardPages blocks, found {count}')
text = text.replace(old_guard_pages, '')

old_compiled_loop = """    for (final pageGuards in guardPages) {
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
"""
new_compiled_loop = """    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),
        build: (_) => _pkk2Page(
          department: department,
          month: month,
          year: year,
          guards: guards,
          sessions: attendanceSessions,
          requiredShift1: requiredByShift[1] ?? 0,
          requiredShift2: requiredByShift[2] ?? 0,
        ),
      ),
    );
"""
if old_compiled_loop not in text:
    raise SystemExit('Compiled PKK2 pagination loop not found')
text = text.replace(old_compiled_loop, new_compiled_loop, 1)

old_pkk2_loop = """    for (final pageGuards in guardPages) {
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
"""
new_pkk2_loop = """    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),
        build: (_) => _pkk2Page(
          department: department,
          month: month,
          year: year,
          guards: guards,
          sessions: sessions,
          requiredShift1: requiredByShift[1] ?? 0,
          requiredShift2: requiredByShift[2] ?? 0,
        ),
      ),
    );
"""
if old_pkk2_loop not in text:
    raise SystemExit('Standalone PKK2 pagination loop not found')
text = text.replace(old_pkk2_loop, new_pkk2_loop, 1)

old_padded_days = """    final paddedDays = <int?>[
      ...days,
      ...List<int?>.filled(10 - days.length, null),
    ];

    pw.Widget sideCell(
"""
new_padded_days = """    final paddedDays = <int?>[
      ...days,
      ...List<int?>.filled(10 - days.length, null),
    ];
    // PKK 2 is one monthly roster. Keep every guard in the same form instead
    // of splitting guard 5+ onto a separate PKK 2 page. For larger teams,
    // compact only the guard rows so the official header/notes stay intact.
    final guardRowCount = math.max(4, guards.length);
    final guardRowHeight = guards.length <= 4
        ? 9.0
        : math.max(4.0, 45.0 / guards.length);
    final guardFontSize = guards.length <= 5
        ? 3.7
        : math.max(2.4, guardRowHeight * 0.42);

    pw.Widget sideCell(
"""
if old_padded_days not in text:
    raise SystemExit('paddedDays anchor not found')
text = text.replace(old_padded_days, new_padded_days, 1)

old_side_signature = """      PdfColor? fill,
      pw.Alignment alignment = pw.Alignment.center,
    }) {
"""
new_side_signature = """      PdfColor? fill,
      pw.Alignment alignment = pw.Alignment.center,
      double fontSize = 3.9,
    }) {
"""
if old_side_signature not in text:
    raise SystemExit('sideCell signature not found')
text = text.replace(old_side_signature, new_side_signature, 1)

old_side_font = """            fontSize: 3.9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
"""
new_side_font = """            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
"""
if old_side_font not in text:
    raise SystemExit('sideCell font anchor not found')
text = text.replace(old_side_font, new_side_font, 1)

old_guard_daily = """                        height: 9,
                        fontSize: 3.7,
"""
new_guard_daily = """                        height: guardRowHeight,
                        fontSize: guardFontSize,
"""
if old_guard_daily not in text:
    raise SystemExit('guardDaily row sizing not found')
text = text.replace(old_guard_daily, new_guard_daily, 1)

old_rows = """        for (var index = 0; index < 4; index++)
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
                        index < guards.length && !guards[index].isReplacement
                            ? 'X'
                            : '',
                        height: 9,
                      ),
                    ),
                    pw.Expanded(
                      child: sideCell(
                        index < guards.length && guards[index].isReplacement
                            ? 'X'
                            : '',
                        height: 9,
                      ),
                    ),
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
"""
new_rows = """        for (var index = 0; index < guardRowCount; index++)
          pw.Row(
            children: [
              pw.SizedBox(
                width: 22,
                child: sideCell(
                  index < guards.length ? '${index + 1}' : '',
                  height: guardRowHeight,
                  fontSize: guardFontSize,
                ),
              ),
              pw.SizedBox(
                width: 155,
                child: sideCell(
                  index < guards.length ? guards[index].name : '',
                  height: guardRowHeight,
                  alignment: pw.Alignment.centerLeft,
                  fontSize: guardFontSize,
                ),
              ),
              pw.SizedBox(
                width: 54,
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: sideCell(
                        index < guards.length && !guards[index].isReplacement
                            ? 'X'
                            : '',
                        height: guardRowHeight,
                        fontSize: guardFontSize,
                      ),
                    ),
                    pw.Expanded(
                      child: sideCell(
                        index < guards.length && guards[index].isReplacement
                            ? 'X'
                            : '',
                        height: guardRowHeight,
                        fontSize: guardFontSize,
                      ),
                    ),
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
                              child: _boxText(
                                '',
                                height: guardRowHeight,
                                fontSize: guardFontSize,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
"""
if old_rows not in text:
    raise SystemExit('Hard-coded four-guard row block not found')
text = text.replace(old_rows, new_rows, 1)

path.write_text(text, encoding='utf-8')
print('PKK 2 updated: all guards now remain in one monthly form.')
