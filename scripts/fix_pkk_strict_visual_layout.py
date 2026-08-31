from pathlib import Path

path = Path('lib/features/admin/pkk_pdf_generator.dart')
text = path.read_text(encoding='utf-8')

old = """    final rows = <_Pkk4Row>[];\n    final days = DateTime(year, month + 1, 0).day;\n    for (var day = 1; day <= days; day++) {\n"""
new = """    final rows = <_Pkk4Row>[];\n    final activeDays = scans\n        .map((row) => (row['_local'] as DateTime).day)\n        .toSet()\n        .toList()\n      ..sort();\n    for (final day in activeDays) {\n"""
if old not in text:
    raise SystemExit('PKK4 day loop anchor not found')
text = text.replace(old, new, 1)

replacements = {
    "margin: const pw.EdgeInsets.fromLTRB(11, 10, 11, 9),":
        "margin: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),",
    "        pw.SizedBox(height: 5),\n        pw.Center(\n          child: pw.Text(\n            'BULAN:":
        "        pw.SizedBox(height: 2),\n        pw.Center(\n          child: pw.Text(\n            'BULAN:",
    "        pw.SizedBox(height: 4),\n        _pkk2Meta(department),\n        pw.SizedBox(height: 5),\n        _pkk2ContractSummary":
        "        pw.SizedBox(height: 2),\n        _pkk2Meta(department),\n        pw.SizedBox(height: 2),\n        _pkk2ContractSummary",
    "        pw.SizedBox(height: 5),\n        pw.Text(\n          '3   SENARAI NAMA":
        "        pw.SizedBox(height: 2),\n        pw.Text(\n          '3   SENARAI NAMA",
    "          _boxText(\n            '1   BILANGAN PENGAWAL":
        "          _boxText(\n            '1   BILANGAN PENGAWAL",
    "            height: 25,\n            fill: PdfColors.grey300,":
        "            height: 18,\n            fill: PdfColors.grey300,",
    "pw.Expanded(child: _boxText('SYIF 1', height: 13))":
        "pw.Expanded(child: _boxText('SYIF 1', height: 9))",
    "pw.Expanded(child: _boxText('SYIF 2', height: 13))":
        "pw.Expanded(child: _boxText('SYIF 2', height: 9))",
    "pw.Expanded(child: _boxText('SYIF 3', height: 13))":
        "pw.Expanded(child: _boxText('SYIF 3', height: 9))",
    "pw.Expanded(child: _boxText('$requiredShift1', height: 13))":
        "pw.Expanded(child: _boxText('$requiredShift1', height: 9))",
    "pw.Expanded(child: _boxText('$requiredShift2', height: 13))":
        "pw.Expanded(child: _boxText('$requiredShift2', height: 9))",
    "pw.Expanded(child: _boxText('', height: 13))":
        "pw.Expanded(child: _boxText('', height: 9))",
    "child: _boxText('Jam 08.00 hingga\\njam 20.00', height: 19)":
        "child: _boxText('Jam 08.00 hingga\\njam 20.00', height: 13)",
    "child: _boxText('Jam 20.00 hingga\\njam 08.00', height: 19)":
        "child: _boxText('Jam 20.00 hingga\\njam 08.00', height: 13)",
    "child: _boxText('Jam ______ hingga\\njam ______', height: 19)":
        "child: _boxText('Jam ______ hingga\\njam ______', height: 13)",
    "                height: 25,\n                bold: true,\n                fill: PdfColors.grey200,":
        "                height: 18,\n                bold: true,\n                fill: PdfColors.grey200,",
    "              child: sideCell('', height: 22, fill: PdfColors.grey200),":
        "              child: sideCell('', height: 16, fill: PdfColors.grey200),",
    "                      height: 22,\n                      bold: true,":
        "                      height: 16,\n                      bold: true,",
    "                  height: 12,\n                ),":
        "                  height: 9,\n                ),",
    "                  height: 12,\n                  alignment: pw.Alignment.centerLeft,":
        "                  height: 9,\n                  alignment: pw.Alignment.centerLeft,",
    "                        height: 12,\n                      ),":
        "                        height: 9,\n                      ),",
    "pw.Expanded(child: sideCell('', height: 12))":
        "pw.Expanded(child: sideCell('', height: 9))",
    "child: _boxText('', height: 12, fontSize: 4)":
        "child: _boxText('', height: 9, fontSize: 3.7)",
    "height: 12,\n                        fontSize: 4.0,":
        "height: 9,\n                        fontSize: 3.7,",
    "if (i != blocks.length - 1) pw.SizedBox(height: 2.4)":
        "if (i != blocks.length - 1) pw.SizedBox(height: 1.0)",
    "        pw.SizedBox(height: 3),\n        _pkk2Note(),\n        pw.SizedBox(height: 2),":
        "        pw.SizedBox(height: 1.5),\n        _pkk2Note(),\n        pw.SizedBox(height: 1),",
    "        pw.SizedBox(height: 3),\n        _signatureRow(),":
        "        pw.SizedBox(height: 1.5),\n        _signatureRow(),",
}

for before, after in replacements.items():
    if before in text:
        text = text.replace(before, after)

# The PKK2 section-2 header has the same 25pt pattern but the first generic
# replacement only changes the first exact occurrence. Make any remaining
# contract-summary header compact as well without touching PKK3/PKK4 tables.
summary_start = text.index('static pw.Widget _pkk2ContractSummary')
summary_end = text.index('static pw.Widget _pkk2AttendanceBlock')
summary = text[summary_start:summary_end].replace('height: 25,', 'height: 18,')
text = text[:summary_start] + summary + text[summary_end:]

# Compact PKK2 attendance block only.
block_start = text.index('static pw.Widget _pkk2AttendanceBlock')
block_end = text.index('static pw.Widget _pkk3Page')
block = text[block_start:block_end]
block = block.replace('height: 25,', 'height: 18,')
block = block.replace('height: 22,', 'height: 16,')
block = block.replace('height: 12,', 'height: 9,')
block = block.replace('fontSize: 4.2,', 'fontSize: 3.9,')
block = block.replace('fontSize: 4.1,', 'fontSize: 3.8,')
block = block.replace('fontSize: 3.8,', 'fontSize: 3.6,')
text = text[:block_start] + block + text[block_end:]

path.write_text(text, encoding='utf-8')
