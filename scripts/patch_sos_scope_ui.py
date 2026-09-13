from pathlib import Path
p=Path('lib/features/admin/sos_management_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import '../../core/api/app_user.dart';\n","import '../../core/api/api_service.dart';\nimport '../../core/api/app_user.dart';\nimport 'admin_scope.dart';\n",'imports')
one("  final SosAlertApi _api = SosAlertApi.instance;","""  final SosAlertApi _api = SosAlertApi.instance;
  final ApiService _coreApi = ApiService.instance;
  final AdminScopeState _scope = AdminScopeState.instance;
  List<CompanyRecord> _companies = const [];
  List<DepartmentRecord> _departments = const [];
  bool _isManagement = false;""",'fields')
one("""    super.initState();
    unawaited(_refresh());""","""    super.initState();
    unawaited(_loadScopeData());
    unawaited(_refresh());""",'init')
one("""  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
""","""  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadScopeData() async {
    try {
      final user = await _coreApi.getSession();
      if (user?.isManagement != true) return;
      final companies = await _coreApi.getAdminCompanies();
      final departments = await _coreApi.getAdminDepartments();
      if (!mounted) return;
      setState(() {
        _isManagement = true;
        _companies = companies;
        _departments = departments;
      });
      await _refresh(silent: true);
    } catch (_) {}
  }
""",'loader')
one("      final events = await _api.fetchManagedEvents();","""      final events = await _api.fetchManagedEvents(
        companyId: _isManagement ? _scope.companyId : null,
        departmentId: _isManagement ? _scope.departmentId : null,
      );""",'request')
one("""                  if (_error != null) ...[""","""                  if (_isManagement && _departments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: AdminScopeFilterBar(
                          companies: _companies,
                          departments: _departments,
                          onChanged: _refresh,
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...[""",'scope UI')
p.write_text(t,encoding='utf-8')
