from pathlib import Path

p = Path('lib/features/admin/user_maintenance_screen.dart')
text = p.read_text(encoding='utf-8')

def rep(old, new):
    global text
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'anchor missing: {old[:100]!r}')
    text = text.replace(old, new, 1)

rep("    final departments = await widget.api.getAdminDepartments();\n    return _UserAdminData(users: users, departments: departments);\n", "    final departments = await widget.api.getAdminDepartments();\n    final companies = await widget.api.getAdminCompanies();\n    return _UserAdminData(users: users, departments: departments, companies: companies);\n")
rep("  Future<void> _addUser(List<DepartmentRecord> departments) async {\n", "  Future<void> _addUser(List<DepartmentRecord> departments, List<CompanyRecord> companies) async {\n")
rep("      builder: (_) => _AddUserDialog(api: widget.api, departments: departments),\n", "      builder: (_) => _AddUserDialog(api: widget.api, departments: departments, companies: companies),\n")
rep("    List<DepartmentRecord> departments,\n  ) async {\n", "    List<DepartmentRecord> departments,\n    List<CompanyRecord> companies,\n  ) async {\n")
rep("        departments: departments,\n      ),\n", "        departments: departments,\n        companies: companies,\n      ),\n")
rep("                              onTap: () => _editUser(user, data.departments),\n", "                              onTap: () => _editUser(user, data.departments, data.companies),\n")
rep("              ? () => _addUser(snapshot.data!.departments)\n", "              ? () => _addUser(snapshot.data!.departments, snapshot.data!.companies)\n")
rep("    required this.departments,\n  });\n\n  final ApiService api;\n  final AppUser user;\n  final List<DepartmentRecord> departments;\n", "    required this.departments,\n    required this.companies,\n  });\n\n  final ApiService api;\n  final AppUser user;\n  final List<DepartmentRecord> departments;\n  final List<CompanyRecord> companies;\n")
rep("class _UserAdminData {\n  const _UserAdminData({required this.users, required this.departments});\n\n  final List<AppUser> users;\n  final List<DepartmentRecord> departments;\n}\n", "class _UserAdminData {\n  const _UserAdminData({required this.users, required this.departments, required this.companies});\n\n  final List<AppUser> users;\n  final List<DepartmentRecord> departments;\n  final List<CompanyRecord> companies;\n}\n")
rep("class _AddUserDialog extends StatefulWidget {\n  const _AddUserDialog({required this.api, required this.departments});\n\n  final ApiService api;\n  final List<DepartmentRecord> departments;\n", "class _AddUserDialog extends StatefulWidget {\n  const _AddUserDialog({required this.api, required this.departments, required this.companies});\n\n  final ApiService api;\n  final List<DepartmentRecord> departments;\n  final List<CompanyRecord> companies;\n")
p.write_text(text, encoding='utf-8')
