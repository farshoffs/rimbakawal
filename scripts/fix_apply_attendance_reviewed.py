from pathlib import Path

p = Path('scripts/apply_attendance_reviewed.py')
text = p.read_text()
old = '''marker = "  Future<AttendanceAdminData> getAdminAttendance(DateTime date, {int? departmentId}) async {\\n"
idx = text.find(marker)
if idx < 0:
    raise SystemExit('getAdminAttendance marker missing')
end = text.find('\\n  Future<', idx + len(marker))
if end < 0:
    raise SystemExit('next API method marker missing')
'''
new = '''marker = "  Future<AttendanceAdminData> getAdminAttendance(DateTime date, {int? departmentId}) async =>\\n"
idx = text.find(marker)
if idx < 0:
    raise SystemExit('getAdminAttendance marker missing')
end = text.find('\\n  String _dateKey', idx + len(marker))
if end < 0:
    raise SystemExit('dateKey marker missing')
'''
if old not in text:
    raise SystemExit('patch script marker block missing')
p.write_text(text.replace(old, new, 1))
