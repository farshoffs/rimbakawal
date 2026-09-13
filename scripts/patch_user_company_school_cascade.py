from pathlib import Path

path = Path('lib/features/admin/user_maintenance_screen.dart')
text = path.read_text(encoding='utf-8')

# Keep user cards compact: three subtitle lines.
old = """                              subtitle: Text(
                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n'
                                '${user.jawatanPaparan} • ${user.guardStatus}\\n'
                                '$companyLabel • $schoolLabel\\n'
                                'Status Akaun: ${user.active ? 'AKTIF' : 'DISEKAT'}',
                              ),"""
new = """                              subtitle: Text(
                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n'
                                '${user.jawatanPaparan} • ${user.guardStatus} • ${user.active ? 'AKTIF' : 'DISEKAT'}\\n'
                                '$companyLabel • $schoolLabel',
                              ),"""
if text.count(old) != 1:
    raise SystemExit(f'user card subtitle: {text.count(old)}')
text = text.replace(old, new, 1)

# Add dialog: default to persistent organization scope and keep school inside company.
add_start = text.index('class _AddUserDialogState')
head, add = text[:add_start], text[add_start:]
old = """    final active = widget.departments.where((item) => item.active).toList();
    if (active.isNotEmpty) _departmentId = active.first.id;
    final companies = widget.companies.where((item) => item.active).toList();
    if (companies.isNotEmpty) _companyId = companies.first.id;"""
new = """    final active = widget.departments.where((item) => item.active).toList();
    final companies = widget.companies.where((item) => item.active).toList();
    final scope = AdminScopeState.instance;
    _companyId = companies.any((item) => item.id == scope.companyId)
        ? scope.companyId
        : (companies.isEmpty ? null : companies.first.id);
    final companySchools = _companyId == null
        ? active
        : active.where((item) => item.companyId == _companyId).toList();
    _departmentId = companySchools.any((item) => item.id == scope.departmentId)
        ? scope.departmentId
        : (companySchools.isEmpty ? null : companySchools.first.id);"""
if add.count(old) != 1:
    raise SystemExit(f'add init: {add.count(old)}')
add = add.replace(old, new, 1)
old = """    final activeCompanies = widget.companies
        .where((item) => item.active)
        .toList();
    final isAdministration = _jawatan == 'Administration';"""
new = """    final activeCompanies = widget.companies
        .where((item) => item.active)
        .toList();
    final companySchools = _companyId == null
        ? active
        : active.where((item) => item.companyId == _companyId).toList();
    final isAdministration = _jawatan == 'Administration';"""
if add.count(old) != 1:
    raise SystemExit(f'add build companySchools: {add.count(old)}')
add = add.replace(old, new, 1)
old = """                      if (value != 'Administration' &&
                          _departmentId == null &&
                          active.isNotEmpty) {
                        _departmentId = active.first.id;
                      }"""
new = """                      if (value != 'Administration') {
                        final schools = _companyId == null
                            ? active
                            : active
                                  .where((item) => item.companyId == _companyId)
                                  .toList();
                        if (!schools.any((item) => item.id == _departmentId)) {
                          _departmentId = schools.isEmpty ? null : schools.first.id;
                        }
                      }"""
if add.count(old) != 1:
    raise SystemExit(f'add role switch: {add.count(old)}')
add = add.replace(old, new, 1)
old = """              else
                DropdownButtonFormField<int>(
                  initialValue: _departmentId,
                  decoration: const InputDecoration(
                    labelText: 'Sekolah',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: active
                      .map(
                        (department) => DropdownMenuItem<int>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _departmentId = value),
                ),"""
new = """              else
                Column(
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey('add-user-company-${_companyId ?? -1}'),
                      initialValue: activeCompanies.any((item) => item.id == _companyId)
                          ? _companyId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Syarikat',
                        prefixIcon: Icon(Icons.business_rounded),
                        helperText: 'Pilih syarikat dahulu untuk mengecilkan senarai sekolah.',
                      ),
                      items: activeCompanies
                          .map((company) => DropdownMenuItem<int>(
                                value: company.id,
                                child: Text(company.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _companyId = value;
                          final schools = value == null
                              ? active
                              : active.where((item) => item.companyId == value).toList();
                          _departmentId = schools.isEmpty ? null : schools.first.id;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('add-user-school-${_companyId ?? -1}-${_departmentId ?? -1}'),
                      initialValue: companySchools.any((item) => item.id == _departmentId)
                          ? _departmentId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sekolah',
                        prefixIcon: Icon(Icons.school_rounded),
                      ),
                      items: companySchools
                          .map((department) => DropdownMenuItem<int>(
                                value: department.id,
                                child: Text(department.name),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _departmentId = value),
                    ),
                  ],
                ),"""
if add.count(old) != 1:
    raise SystemExit(f'add school block: {add.count(old)}')
add = add.replace(old, new, 1)
text = head + add

# Edit dialog: use selected company to constrain school choices.
edit_start = text.index('class _EditUserDialogState')
add_start = text.index('class _AddUserDialogState')
head, edit, tail = text[:edit_start], text[edit_start:add_start], text[add_start:]
old = """    final activeCompanies = widget.companies
        .where((item) => item.active || item.id == _companyId)
        .toList();
    final isAdministration = _jawatan == 'Administration';"""
new = """    final activeCompanies = widget.companies
        .where((item) => item.active || item.id == _companyId)
        .toList();
    final companySchools = _companyId == null
        ? active
        : active.where((item) => item.companyId == _companyId).toList();
    final isAdministration = _jawatan == 'Administration';"""
if edit.count(old) != 1:
    raise SystemExit(f'edit build companySchools: {edit.count(old)}')
edit = edit.replace(old, new, 1)
old = """                            if (value != 'Administration' &&
                                _departmentId == null &&
                                active.isNotEmpty) {
                              _departmentId = active.first.id;
                            }"""
new = """                            if (value != 'Administration') {
                              final schools = _companyId == null
                                  ? active
                                  : active
                                        .where((item) => item.companyId == _companyId)
                                        .toList();
                              if (!schools.any((item) => item.id == _departmentId)) {
                                _departmentId = schools.isEmpty ? null : schools.first.id;
                              }
                            }"""
if edit.count(old) != 1:
    raise SystemExit(f'edit role switch: {edit.count(old)}')
edit = edit.replace(old, new, 1)
old = """              else
                DropdownButtonFormField<int>(
                  initialValue: _departmentId,
                  decoration: const InputDecoration(
                    labelText: 'Sekolah',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: active
                      .map(
                        (department) => DropdownMenuItem<int>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _departmentId = value),
                ),"""
new = """              else
                Column(
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey('edit-user-company-${_companyId ?? -1}'),
                      initialValue: activeCompanies.any((item) => item.id == _companyId)
                          ? _companyId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Syarikat',
                        prefixIcon: Icon(Icons.business_rounded),
                        helperText: 'Menukar syarikat akan meminta pemilihan sekolah di bawah syarikat tersebut.',
                      ),
                      items: activeCompanies
                          .map((company) => DropdownMenuItem<int>(
                                value: company.id,
                                child: Text(company.name),
                              ))
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _companyId = value;
                                final schools = value == null
                                    ? active
                                    : active.where((item) => item.companyId == value).toList();
                                _departmentId = schools.isEmpty ? null : schools.first.id;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('edit-user-school-${_companyId ?? -1}-${_departmentId ?? -1}'),
                      initialValue: companySchools.any((item) => item.id == _departmentId)
                          ? _departmentId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sekolah',
                        prefixIcon: Icon(Icons.school_rounded),
                      ),
                      items: companySchools
                          .map((department) => DropdownMenuItem<int>(
                                value: department.id,
                                child: Text(department.name),
                              ))
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _departmentId = value),
                    ),
                  ],
                ),"""
if edit.count(old) != 1:
    raise SystemExit(f'edit school block: {edit.count(old)}')
edit = edit.replace(old, new, 1)
path.write_text(head + edit + tail, encoding='utf-8')
