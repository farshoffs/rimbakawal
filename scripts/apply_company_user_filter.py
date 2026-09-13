from pathlib import Path

path = Path('lib/features/admin/user_maintenance_screen.dart')
text = path.read_text(encoding='utf-8')

old = """  late Future<_UserAdminData> _future;\n  int _departmentFilterId = -1;\n"""
new = """  late Future<_UserAdminData> _future;\n  int _companyFilterId = -1;\n  int _departmentFilterId = -1;\n"""
if old not in text:
    raise SystemExit('state filter anchor not found')
text = text.replace(old, new, 1)

old = """          final data = snapshot.data!;\n          final filteredUsers = _departmentFilterId == -1\n              ? data.users\n              : data.users\n                    .where((user) => user.departmentId == _departmentFilterId)\n                    .toList();\n          return Column(\n"""
new = """          final data = snapshot.data!;\n          final departmentsById = {\n            for (final department in data.departments) department.id: department,\n          };\n          final companyDepartments = _companyFilterId == -1\n              ? data.departments\n              : data.departments\n                    .where((department) => department.companyId == _companyFilterId)\n                    .toList();\n          final filteredUsers = data.users.where((user) {\n            final resolvedCompanyId =\n                user.companyId ?? departmentsById[user.departmentId]?.companyId;\n            final matchesCompany =\n                _companyFilterId == -1 || resolvedCompanyId == _companyFilterId;\n            final matchesDepartment =\n                _departmentFilterId == -1 ||\n                user.departmentId == _departmentFilterId;\n            return matchesCompany && matchesDepartment;\n          }).toList();\n          return Column(\n"""
if old not in text:
    raise SystemExit('filtered users anchor not found')
text = text.replace(old, new, 1)

old = """              Padding(\n                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),\n                child: DropdownButtonFormField<int>(\n                  initialValue: _departmentFilterId,\n                  decoration: const InputDecoration(\n                    labelText: 'Filter Sekolah',\n                    prefixIcon: Icon(Icons.filter_alt_rounded),\n                  ),\n                  items: [\n                    const DropdownMenuItem<int>(\n                      value: -1,\n                      child: Text('Semua Sekolah'),\n                    ),\n                    ...data.departments.map(\n                      (department) => DropdownMenuItem<int>(\n                        value: department.id,\n                        child: Text(department.name),\n                      ),\n                    ),\n                  ],\n                  onChanged: (value) =>\n                      setState(() => _departmentFilterId = value ?? -1),\n                ),\n              ),\n"""
new = """              Padding(\n                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),\n                child: DropdownButtonFormField<int>(\n                  initialValue: _companyFilterId,\n                  decoration: const InputDecoration(\n                    labelText: 'Filter Syarikat',\n                    prefixIcon: Icon(Icons.business_rounded),\n                  ),\n                  items: [\n                    const DropdownMenuItem<int>(\n                      value: -1,\n                      child: Text('Semua Syarikat'),\n                    ),\n                    ...data.companies.map(\n                      (company) => DropdownMenuItem<int>(\n                        value: company.id,\n                        child: Text(company.name),\n                      ),\n                    ),\n                  ],\n                  onChanged: (value) {\n                    setState(() {\n                      _companyFilterId = value ?? -1;\n                      _departmentFilterId = -1;\n                    });\n                  },\n                ),\n              ),\n              Padding(\n                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),\n                child: DropdownButtonFormField<int>(\n                  key: ValueKey(\n                    'department-filter-$_companyFilterId-$_departmentFilterId',\n                  ),\n                  initialValue: _departmentFilterId,\n                  decoration: const InputDecoration(\n                    labelText: 'Filter Sekolah',\n                    prefixIcon: Icon(Icons.account_tree_outlined),\n                  ),\n                  items: [\n                    const DropdownMenuItem<int>(\n                      value: -1,\n                      child: Text('Semua Sekolah'),\n                    ),\n                    ...companyDepartments.map(\n                      (department) => DropdownMenuItem<int>(\n                        value: department.id,\n                        child: Text(department.name),\n                      ),\n                    ),\n                  ],\n                  onChanged: (value) =>\n                      setState(() => _departmentFilterId = value ?? -1),\n                ),\n              ),\n"""
if old not in text:
    raise SystemExit('school filter widget anchor not found')
text = text.replace(old, new, 1)

text = text.replace(
    "const Center(child: Text('Tiada pengguna untuk Sekolah ini.'))",
    "const Center(child: Text('Tiada pengguna untuk penapis dipilih.'))",
    1,
)

path.write_text(text, encoding='utf-8')
print('Applied company filter to Pengguna Syarikat screen')
