from pathlib import Path

p = Path('lib/features/admin/department_maintenance_screen.dart')
text = p.read_text(encoding='utf-8')

def rep(old, new):
    global text
    if old not in text:
        if new in text:
            return
        raise RuntimeError(f'anchor missing: {old[:100]!r}')
    text = text.replace(old, new, 1)

rep("  late final TextEditingController _companyController;\n  late final TextEditingController _zoneController;\n", "  late final TextEditingController _zoneController;\n  late Future<List<CompanyRecord>> _companiesFuture;\n  int? _companyId;\n")
rep("    _companyController = TextEditingController(\n      text: widget.department?.companyName ?? '',\n    );\n    _zoneController = TextEditingController(\n", "    _companyId = widget.department?.companyId;\n    _companiesFuture = widget.api.getAdminCompanies();\n    _zoneController = TextEditingController(\n")
# Remove the obsolete controller independently; checking only the replacement
# text here is unsafe because _zoneController.dispose() already exists in the old block.
if "    _companyController.dispose();\n" in text:
    text = text.replace("    _companyController.dispose();\n", "", 1)
rep("    if (_latitude == null || _longitude == null) {\n", "    if (_companyId == null) {\n      setState(() => _error = 'Pilih Syarikat yang mengendalikan Sekolah ini.');\n      return;\n    }\n    if (_latitude == null || _longitude == null) {\n")
rep("          companyName: _companyController.text.trim(),\n          zone: _zoneController.text.trim(),\n", "          companyId: _companyId,\n          zone: _zoneController.text.trim(),\n")
rep("            companyName: _companyController.text.trim(),\n            zone: _zoneController.text.trim(),\n", "            companyId: _companyId,\n            companyName: existing.companyName,\n            zone: _zoneController.text.trim(),\n")
rep('''              TextField(\n                controller: _companyController,\n                textCapitalization: TextCapitalization.characters,\n                decoration: const InputDecoration(\n                  labelText: 'Nama Syarikat',\n                  prefixIcon: Icon(Icons.business_rounded),\n                  helperText: 'Digunakan dalam borang BPPA PKK 2 dan PKK 3.',\n                ),\n              ),\n''', '''              FutureBuilder<List<CompanyRecord>>(\n                future: _companiesFuture,\n                builder: (context, snapshot) {\n                  final companies = (snapshot.data ?? const <CompanyRecord>[])\n                      .where((item) => item.active || item.id == _companyId)\n                      .toList();\n                  return DropdownButtonFormField<int>(\n                    initialValue: companies.any((item) => item.id == _companyId) ? _companyId : null,\n                    decoration: InputDecoration(\n                      labelText: 'Syarikat',\n                      prefixIcon: const Icon(Icons.business_rounded),\n                      helperText: companies.isEmpty\n                          ? 'Cipta Syarikat melalui menu Pengurusan Syarikat dahulu.'\n                          : 'Pilih syarikat induk yang mengendalikan Sekolah ini.',\n                    ),\n                    items: companies\n                        .map((company) => DropdownMenuItem<int>(\n                              value: company.id,\n                              child: Text(company.name),\n                            ))\n                        .toList(),\n                    onChanged: _saving || companies.isEmpty\n                        ? null\n                        : (value) => setState(() => _companyId = value),\n                  );\n                },\n              ),\n''')
p.write_text(text, encoding='utf-8')
