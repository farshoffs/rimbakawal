from pathlib import Path

path = Path('lib/features/admin/user_maintenance_screen.dart')
text = path.read_text(encoding='utf-8')

def one(old, new, label):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected 1, found {n}')
    text = text.replace(old, new, 1)

one("import '../../core/api/app_user.dart';\n", "import '../../core/api/app_user.dart';\nimport 'admin_scope.dart';\n", 'import')
one(
"""  late Future<_UserAdminData> _future;
  int _companyFilterId = -1;
  int _departmentFilterId = -1;""",
"""  late Future<_UserAdminData> _future;
  final AdminScopeState _scope = AdminScopeState.instance;
  final TextEditingController _searchController = TextEditingController();
  String _roleFilter = 'all';
  String _statusFilter = 'all';""",
'state')
one(
"""  void _refresh() {
    setState(() => _future = _load());
  }

  Future<_UserAdminData> _load() async {
    final users = (await widget.api.getAdminUsers())""",
"""  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_UserAdminData> _load() async {
    final users = (await widget.api.getAdminUsers(
      companyId: _scope.companyId,
      departmentId: _scope.departmentId,
    ))""",
'load')
one(
"""          final companyDepartments = _companyFilterId == -1
              ? data.departments
              : data.departments
                    .where(
                      (department) => department.companyId == _companyFilterId,
                    )
                    .toList();
          final filteredUsers = data.users.where((user) {
            final resolvedCompanyId =
                user.companyId ?? departmentsById[user.departmentId]?.companyId;
            final matchesCompany =
                _companyFilterId == -1 || resolvedCompanyId == _companyFilterId;
            final matchesDepartment =
                _departmentFilterId == -1 ||
                user.departmentId == _departmentFilterId;
            return matchesCompany && matchesDepartment;
          }).toList();""",
"""          final query = _searchController.text.trim().toLowerCase();
          final filteredUsers = data.users.where((user) {
            final role = user.jawatan.toLowerCase();
            final matchesRole = _roleFilter == 'all' || role == _roleFilter;
            final matchesStatus = _statusFilter == 'all' ||
                (_statusFilter == 'active' ? user.active : !user.active);
            final department = departmentsById[user.departmentId];
            final companyName = user.companyName.isNotEmpty
                ? user.companyName
                : (department?.companyName ?? '');
            final haystack = [
              user.nama,
              user.noKadPengenalan,
              user.noPk,
              user.jabatan,
              companyName,
              user.jawatanPaparan,
            ].join(' ').toLowerCase();
            return matchesRole && matchesStatus &&
                (query.isEmpty || haystack.contains(query));
          }).toList();""",
'filter logic')
one(
"""                          final user = filteredUsers[index];
                          return Card(""",
"""                          final user = filteredUsers[index];
                          final department = departmentsById[user.departmentId];
                          final companyLabel = user.companyName.isNotEmpty
                              ? user.companyName
                              : (department?.companyName ?? 'Syarikat belum ditetapkan');
                          final schoolLabel = user.isAdministration
                              ? 'Semua sekolah syarikat'
                              : user.jabatan;
                          return Card(""",
'card vars')
one(
"""                              subtitle: Text(
                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.guardStatus} • ${user.jabatan}\\nStatus Akaun: ${user.active ? 'AKTIF' : 'DISEKAT'}',
                              ),""",
"""                              subtitle: Text(
                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n'
                                '${user.jawatanPaparan} • ${user.guardStatus}\\n'
                                '$companyLabel • $schoolLabel\\n'
                                'Status Akaun: ${user.active ? 'AKTIF' : 'DISEKAT'}',
                              ),""",
'card subtitle')
path.write_text(text, encoding='utf-8')
