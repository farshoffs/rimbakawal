from pathlib import Path
p=Path('lib/features/admin/command_center_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("import '../../core/api/api_service.dart';\n","import '../../core/api/api_service.dart';\nimport 'admin_scope.dart';\n",'import')
one("  final _attendanceKey = GlobalKey();","""  final _attendanceKey = GlobalKey();
  final AdminScopeState _scope = AdminScopeState.instance;
  List<CompanyRecord> _companies = const [];
  List<DepartmentRecord> _departments = const [];
  bool _isManagement = false;""",'fields')
one("""    _recalculateRange();
    unawaited(_refresh());""","""    _recalculateRange();
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
      await _refresh(silent: true);
    } catch (_) {}
  }
""",'loader')
one("""        mode: _mode.name,
      );""","""        mode: _mode.name,
        companyId: _isManagement ? _scope.companyId : null,
        departmentId: _isManagement ? _scope.departmentId : null,
      );""",'request')
one("""                  children: [
                    _PeriodFilter(""","""                  children: [
                    if (_isManagement && _departments.isNotEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Skop Pemantauan', style: TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 10),
                              AdminScopeFilterBar(
                                companies: _companies,
                                departments: _departments,
                                onChanged: _refresh,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _PeriodFilter(""",'scope UI')
p.write_text(t,encoding='utf-8')
