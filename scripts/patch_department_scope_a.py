from pathlib import Path
p=Path('lib/features/admin/department_maintenance_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import '../../core/nfc/nfc_service.dart';\n","import '../../core/nfc/nfc_service.dart';\nimport 'admin_scope.dart';\n",'import')
one("""  late Future<List<DepartmentRecord>> _future;
  int _refreshKey = 0;""","""  late Future<List<DepartmentRecord>> _future;
  int _refreshKey = 0;
  final AdminScopeState _scope = AdminScopeState.instance;
  final TextEditingController _searchController = TextEditingController();""",'state')
one("""  void _refresh() {
    setState(() {
      _refreshKey++;
      _future = widget.api.getAdminDepartments();
    });
  }""","""  void _refresh() {
    setState(() {
      _refreshKey++;
      _future = widget.api.getAdminDepartments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }""",'dispose')
one("""          final departments = snapshot.data ?? const <DepartmentRecord>[];
          if (departments.isEmpty) {""","""          final departments = snapshot.data ?? const <DepartmentRecord>[];
          final companies = companiesFromDepartments(departments);
          final companyId = _scope.effectiveCompanyId(companies);
          final companyDepartments = companyId == null
              ? departments
              : departments.where((item) => item.companyId == companyId).toList();
          final departmentId = _scope.effectiveDepartmentId(companyDepartments);
          final query = _searchController.text.trim().toLowerCase();
          final visibleDepartments = companyDepartments.where((item) {
            final matchesSchool = departmentId == null || item.id == departmentId;
            final haystack = '${item.name} ${item.companyName} ${item.zone}'.toLowerCase();
            return matchesSchool && (query.isEmpty || haystack.contains(query));
          }).toList();
          if (departments.isEmpty) {""",'derive')
p.write_text(t,encoding='utf-8')
