from pathlib import Path
p=Path('lib/features/history/clocking_history_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import '../../core/api/app_user.dart';\n","import '../../core/api/app_user.dart';\nimport '../admin/admin_scope.dart';\n",'import')
one("""  List<DepartmentRecord> _departments = const [];
  late Future<HistoryDay> _future;""","""  List<DepartmentRecord> _departments = const [];
  List<CompanyRecord> _companies = const [];
  final AdminScopeState _scope = AdminScopeState.instance;
  late Future<HistoryDay> _future;""",'fields')
one("""    final departments = await widget.api.getAdminDepartments();
    final selected =
        _selectedDepartmentId ??
        (departments.isEmpty ? null : departments.first.id);
    if (mounted) {
      setState(() {
        _departments = departments;
        _selectedDepartmentId = selected;
      });
    }""","""    final departments = await widget.api.getAdminDepartments();
    final companies = companiesFromDepartments(departments);
    final companyId = _scope.effectiveCompanyId(companies);
    final scopedDepartments = companyId == null
        ? departments
        : departments.where((item) => item.companyId == companyId).toList();
    final scopeDepartment = _scope.effectiveDepartmentId(scopedDepartments);
    final selected = scopeDepartment ??
        (_selectedDepartmentId != null &&
                scopedDepartments.any((item) => item.id == _selectedDepartmentId)
            ? _selectedDepartmentId
            : (scopedDepartments.isEmpty ? null : scopedDepartments.first.id));
    if (selected != null) _scope.setDepartment(selected);
    if (mounted) {
      setState(() {
        _departments = departments;
        _companies = companies;
        _selectedDepartmentId = selected;
      });
    }""",'initial')
one("""    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));""","""    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final companyId = _scope.effectiveCompanyId(_companies);
    final managementDepartments = companyId == null
        ? _departments
        : _departments.where((item) => item.companyId == companyId).toList();""",'build scope')
one("""                      if (widget.user.isManagement) ...[
                        DropdownButtonFormField<int>(""","""                      if (widget.user.isManagement) ...[
                        AdminScopeFilterBar(
                          companies: _companies,
                          departments: _departments,
                          showSchool: false,
                          onChanged: () {
                            final companyId = _scope.effectiveCompanyId(_companies);
                            final schools = companyId == null
                                ? _departments
                                : _departments.where((item) => item.companyId == companyId).toList();
                            if (schools.isNotEmpty) {
                              final next = schools.first.id;
                              _scope.setDepartment(next);
                              _load(_selectedDate, departmentId: next);
                            } else {
                              setState(() => _selectedDepartmentId = null);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(""",'company filter')
one("""                          items: _departments
                              .map(""","""                          items: managementDepartments
                              .map(""",'school list')
one("""                            if (value != null) {
                              _load(_selectedDate, departmentId: value);
                            }""","""                            if (value != null) {
                              _scope.setDepartment(value);
                              _load(_selectedDate, departmentId: value);
                            }""",'school persist')
p.write_text(t,encoding='utf-8')
