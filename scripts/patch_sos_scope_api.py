from pathlib import Path
p=Path('lib/features/sos/sos_alert_api.dart')
t=p.read_text(encoding='utf-8')
old="""  Future<List<Map<String, dynamic>>> fetchManagedEvents() async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/api/sos/manage'),
      headers: await _headers(),
    );"""
new="""  Future<List<Map<String, dynamic>>> fetchManagedEvents({
    int? companyId,
    int? departmentId,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/sos/manage').replace(
      queryParameters: {
        if (companyId != null) 'companyId': companyId.toString(),
        if (departmentId != null) 'departmentId': departmentId.toString(),
      },
    );
    final response = await http.get(
      uri,
      headers: await _headers(),
    );"""
if t.count(old)!=1: raise SystemExit(f'fetch managed {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
