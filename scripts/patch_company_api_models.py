from pathlib import Path

p = Path('lib/core/api/api_service.dart')
text = p.read_text(encoding='utf-8')

def rep(old, new):
    global text
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'anchor missing: {old[:80]!r}')
    text = text.replace(old, new, 1)

rep('class DepartmentRecord {\n', '''class CompanyRecord {\n  const CompanyRecord({\n    required this.id,\n    required this.name,\n    required this.active,\n    this.schoolCount = 0,\n    this.administrationCount = 0,\n  });\n  final int id;\n  final String name;\n  final bool active;\n  final int schoolCount;\n  final int administrationCount;\n\n  factory CompanyRecord.fromJson(Map<String, dynamic> json) => CompanyRecord(\n    id: (json['id'] as num).toInt(),\n    name: json['name'] as String? ?? '',\n    active: json['active'] as bool? ?? true,\n    schoolCount: (json['schoolCount'] as num?)?.toInt() ?? 0,\n    administrationCount: (json['administrationCount'] as num?)?.toInt() ?? 0,\n  );\n}\n\nclass DepartmentRecord {\n''')
rep("    this.attendanceLocationLabel = '',\n    this.companyName = '',\n", "    this.attendanceLocationLabel = '',\n    this.companyId,\n    this.companyName = '',\n")
rep("  final String attendanceLocationLabel;\n  final String companyName;\n", "  final String attendanceLocationLabel;\n  final int? companyId;\n  final String companyName;\n")
rep("    attendanceLocationLabel: json['attendanceLocationLabel'] as String? ?? '',\n    companyName: json['companyName'] as String? ?? '',\n", "    attendanceLocationLabel: json['attendanceLocationLabel'] as String? ?? '',\n    companyId: (json['companyId'] as num?)?.toInt(),\n    companyName: json['companyName'] as String? ?? '',\n")
rep('  Future<List<DepartmentRecord>> getAdminDepartments() async {\n', '''  Future<List<CompanyRecord>> getAdminCompanies() async {\n    final data = _decode(await _cachedGet(_uri('/api/admin/companies'), headers: _headers()));\n    return (data['companies'] as List<dynamic>? ?? const [])\n        .map((item) => CompanyRecord.fromJson(Map<String, dynamic>.from(item as Map)))\n        .toList();\n  }\n\n  Future<CompanyRecord> createCompany(String name) async {\n    final data = _decode(await http.post(\n      _uri('/api/admin/companies'),\n      headers: _headers(jsonBody: true),\n      body: jsonEncode({'name': name}),\n    ));\n    return CompanyRecord.fromJson(Map<String, dynamic>.from(data['company'] as Map));\n  }\n\n  Future<CompanyRecord> updateCompany(CompanyRecord company) async {\n    final data = _decode(await http.put(\n      _uri('/api/admin/companies/${company.id}'),\n      headers: _headers(jsonBody: true),\n      body: jsonEncode({'name': company.name, 'active': company.active}),\n    ));\n    return CompanyRecord.fromJson(Map<String, dynamic>.from(data['company'] as Map));\n  }\n\n  Future<List<DepartmentRecord>> getAdminDepartments() async {\n''')
p.write_text(text, encoding='utf-8')
