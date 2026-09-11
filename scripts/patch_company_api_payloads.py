from pathlib import Path

p = Path('lib/core/api/api_service.dart')
text = p.read_text(encoding='utf-8')

def rep(old, new):
    global text
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'anchor missing: {old[:90]!r}')
    text = text.replace(old, new, 1)

rep("    String companyName = '',\n    String zone = '',\n", "    int? companyId,\n    String zone = '',\n")
rep("          'companyName': companyName,\n          'zone': zone,\n", "          'companyId': companyId,\n          'zone': zone,\n")
rep("          'companyName': department.companyName,\n          'zone': department.zone,\n", "          'companyId': department.companyId,\n          'zone': department.zone,\n")
rep('''  Future<AppUser> createAdminUser({\n    required String nama,\n    required String noKadPengenalan,\n    required String jawatan,\n    required int departmentId,\n''', '''  Future<AppUser> createAdminUser({\n    required String nama,\n    required String noKadPengenalan,\n    required String jawatan,\n    int? departmentId,\n    int? companyId,\n''')
rep("          'jawatan': jawatan,\n          'departmentId': departmentId,\n          'noPk': noPk,\n", "          'jawatan': jawatan,\n          if (departmentId != null) 'departmentId': departmentId,\n          if (companyId != null) 'companyId': companyId,\n          'noPk': noPk,\n")
rep('''  Future<AppUser> updateAdminUser({\n    required int userId,\n    required String nama,\n    required String jawatan,\n    required int departmentId,\n''', '''  Future<AppUser> updateAdminUser({\n    required int userId,\n    required String nama,\n    required String jawatan,\n    int? departmentId,\n    int? companyId,\n''')
rep("      'jawatan': jawatan,\n      'departmentId': departmentId,\n      'noPk': noPk,\n", "      'jawatan': jawatan,\n      if (departmentId != null) 'departmentId': departmentId,\n      if (companyId != null) 'companyId': companyId,\n      'noPk': noPk,\n")
p.write_text(text, encoding='utf-8')
