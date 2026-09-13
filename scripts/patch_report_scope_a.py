from pathlib import Path
p=Path('lib/features/admin/report_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import 'pkk_pdf_generator.dart';\n","import 'admin_scope.dart';\nimport 'pkk_pdf_generator.dart';\n",'import')
one("  int? _departmentId;","  int? _departmentId;\n  final AdminScopeState _scope = AdminScopeState.instance;",'field')
one("""        if (_departmentId == null && active.length == 1) {
          _departmentId = active.first.id;
        }""","""        final scopedDepartment = _scope.effectiveDepartmentId(active);
        if (widget.user?.isAdministration != true && scopedDepartment != null) {
          _departmentId = scopedDepartment;
        } else if (_departmentId == null && active.length == 1) {
          _departmentId = active.first.id;
        }""",'initial')
one("""    final isCompanyAdmin = widget.user?.isAdministration == true;
    final companyName = widget.user?.companyName ?? '';""","""    final isCompanyAdmin = widget.user?.isAdministration == true;
    final companyName = widget.user?.companyName ?? '';
    final companies = companiesFromDepartments(_departments);
    final scopedCompanyId = isCompanyAdmin ? null : _scope.effectiveCompanyId(companies);
    final scopedDepartments = scopedCompanyId == null
        ? _departments
        : _departments.where((item) => item.companyId == scopedCompanyId).toList();""",'collections')
p.write_text(t,encoding='utf-8')
