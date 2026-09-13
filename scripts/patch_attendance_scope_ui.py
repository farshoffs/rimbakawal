from pathlib import Path
p=Path('lib/features/admin/attendance_history_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import '../../core/api/api_service.dart';\n","import '../../core/api/api_service.dart';\nimport 'admin_scope.dart';\n",'import')
one("  int _departmentFilterId = -1;","  int _companyFilterId = -1;\n  int _departmentFilterId = -1;\n  final AdminScopeState _scope = AdminScopeState.instance;",'state')
one("""    _departmentsFuture = widget.api.getAdminDepartments();
    _future = widget.api.getAdminAttendance(_date);""","""    _companyFilterId = _scope.companyId ?? -1;
    _departmentFilterId = _scope.departmentId ?? -1;
    _departmentsFuture = widget.api.getAdminDepartments();
    _future = widget.api.getAdminAttendance(
      _date,
      companyId: _scope.companyId,
      departmentId: _scope.departmentId,
    );""",'init')
one("""      _date,
      departmentId: _departmentFilterId == -1 ? null : _departmentFilterId,
    ),""","""      _date,
      companyId: _companyFilterId == -1 ? null : _companyFilterId,
      departmentId: _departmentFilterId == -1 ? null : _departmentFilterId,
    ),""",'refresh')
old="""                    return DropdownButtonFormField<int>(
                      initialValue: _departmentFilterId,
                      decoration: const InputDecoration(
                        labelText: 'Filter Sekolah',
                        prefixIcon: Icon(Icons.school_rounded),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: -1,
                          child: Text('Semua Sekolah'),
                        ),
                        ...departments.map(
                          (department) => DropdownMenuItem<int>(
                            value: department.id,
                            child: Text(department.name),
                          ),
                        ),
                      ],
                      onChanged:
                          departmentSnapshot.connectionState ==
                              ConnectionState.waiting
                          ? null
                          : (value) {
                              _departmentFilterId = value ?? -1;
                              _refresh();
                            },
                    );"""
new="""                    final companies = companiesFromDepartments(departments);
                    return AdminScopeFilterBar(
                      companies: companies,
                      departments: departments,
                      onChanged: () {
                        _companyFilterId = _scope.companyId ?? -1;
                        _departmentFilterId = _scope.departmentId ?? -1;
                        _refresh();
                      },
                    );"""
one(old,new,'filter widget')
p.write_text(t,encoding='utf-8')
