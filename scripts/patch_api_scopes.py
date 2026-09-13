from pathlib import Path

path = Path('lib/core/api/api_service.dart')
text = path.read_text(encoding='utf-8')

def one(old, new, label):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected 1, found {n}')
    text = text.replace(old, new, 1)

one(
"""  Future<LiveMapData> getLiveMap() async => LiveMapData.fromJson(
    _decode(
      await _cachedGet(_uri('/api/monitor/live-map'), headers: _headers()),
    ),
  );""",
"""  Future<LiveMapData> getLiveMap({
    int? companyId,
    int? departmentId,
  }) async => LiveMapData.fromJson(
    _decode(
      await _cachedGet(
        _uri('/api/monitor/live-map', {
          if (companyId != null) 'companyId': companyId.toString(),
          if (departmentId != null) 'departmentId': departmentId.toString(),
        }),
        headers: _headers(),
      ),
    ),
  );""",
'live map')

one(
"""  Future<CommandCenterData> getCommandCenter({
    DateTime? from,
    DateTime? to,
    String mode = 'day',
  }) async {""",
"""  Future<CommandCenterData> getCommandCenter({
    DateTime? from,
    DateTime? to,
    String mode = 'day',
    int? companyId,
    int? departmentId,
  }) async {""",
'command signature')

one(
"""            'mode': mode,
          }),""",
"""            'mode': mode,
            if (companyId != null) 'companyId': companyId.toString(),
            if (departmentId != null) 'departmentId': departmentId.toString(),
          }),""",
'command query')

one(
"""  Future<List<AppUser>> getAdminUsers() async {
    final data = _decode(
      await _cachedGet(_uri('/api/admin/users'), headers: _headers()),
    );""",
"""  Future<List<AppUser>> getAdminUsers({
    int? companyId,
    int? departmentId,
  }) async {
    final data = _decode(
      await _cachedGet(
        _uri('/api/admin/users', {
          if (companyId != null) 'companyId': companyId.toString(),
          if (departmentId != null) 'departmentId': departmentId.toString(),
        }),
        headers: _headers(),
      ),
    );""",
'users')

one(
"""  Future<AttendanceAdminData> getAdminAttendance(
    DateTime date, {
    int? departmentId,
  }) async => AttendanceAdminData.fromJson(""",
"""  Future<AttendanceAdminData> getAdminAttendance(
    DateTime date, {
    int? departmentId,
    int? companyId,
  }) async => AttendanceAdminData.fromJson(""",
'attendance signature')

idx = text.index('Future<AttendanceAdminData> getAdminAttendance')
head, tail = text[:idx], text[idx:]
old = """          if (departmentId != null) 'departmentId': departmentId.toString(),
        }),"""
new = """          if (departmentId != null) 'departmentId': departmentId.toString(),
          if (companyId != null) 'companyId': companyId.toString(),
        }),"""
if tail.count(old) < 1:
    raise SystemExit('attendance query block missing')
tail = tail.replace(old, new, 1)
path.write_text(head + tail, encoding='utf-8')
