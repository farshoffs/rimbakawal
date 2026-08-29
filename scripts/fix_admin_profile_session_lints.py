from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
api_path = ROOT / 'lib/core/api/api_service.dart'
api = api_path.read_text(encoding='utf-8')

old_cached = '    final cached = await _offline.cachedUser();\n'
new_cached = '    final cached = _offline.cachedUser();\n'
if old_cached not in api:
    raise SystemExit('Marker cachedUser lint tidak ditemui')
api = api.replace(old_cached, new_cached, 1)

old_body = """    final body = <String, dynamic>{
      'nama': nama,
      'jawatan': jawatan,
      'departmentId': departmentId,
      if (profilePicture != null) 'profilePicture': profilePicture,
      if (clearProfilePicture) 'clearProfilePicture': true,
    };
"""
new_body = """    final body = <String, dynamic>{
      'nama': nama,
      'jawatan': jawatan,
      'departmentId': departmentId,
    };
    if (profilePicture != null) body['profilePicture'] = profilePicture;
    if (clearProfilePicture) body['clearProfilePicture'] = true;
"""
if old_body not in api:
    raise SystemExit('Marker admin update body lint tidak ditemui')
api = api.replace(old_body, new_body, 1)

api_path.write_text(api, encoding='utf-8')
print('Lint fixes applied.')
