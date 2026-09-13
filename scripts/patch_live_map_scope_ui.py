from pathlib import Path
p=Path('lib/features/admin/live_patrol_map_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import '../../core/api/api_service.dart';\n","import '../../core/api/api_service.dart';\nimport 'admin_scope.dart';\n",'import')
one("  int? _selectedUserId;","""  int? _selectedUserId;
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
    _mapController.dispose();
    super.dispose();
  }
""","""  @override
  void dispose() {
    _timer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadScopeData() async {
    try {
      final user = await widget.api.getSession();
      if (user?.isManagement != true) return;
      final companies = await widget.api.getAdminCompanies();
      final departments = await widget.api.getAdminDepartments();
      if (!mounted) return;
      setState(() {
        _isManagement = true;
        _companies = companies;
        _departments = departments;
      });
      _didFit = false;
      await _refresh(silent: true);
    } catch (_) {}
  }
""",'loader')
one("      final data = await widget.api.getLiveMap();","""      final data = await widget.api.getLiveMap(
        companyId: _isManagement ? _scope.companyId : null,
        departmentId: _isManagement ? _scope.departmentId : null,
      );""",'request')
one("""                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _MapHeader(""","""                if (_isManagement && _departments.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: AdminScopeFilterBar(
                          companies: _companies,
                          departments: _departments,
                          onChanged: () {
                            _didFit = false;
                            _refresh();
                          },
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: _isManagement && _departments.isNotEmpty ? 150 : 12,
                  left: 12,
                  right: 12,
                  child: _MapHeader(""",'overlay')
p.write_text(t,encoding='utf-8')
