from pathlib import Path

path = Path('lib/features/admin/user_maintenance_screen.dart')
text = path.read_text(encoding='utf-8')
old = """      await widget.api.createAdminUser(
        nama: name,
        noKadPengenalan: ic,
        jawatan: _jawatan,
        departmentId: _departmentId!,
        noPk: _noPkController.text.trim(),
        guardStatus: _guardStatus,
      );"""
new = """      await widget.api.createAdminUser(
        nama: name,
        noKadPengenalan: ic,
        jawatan: _jawatan,
        departmentId: isAdministration ? null : _departmentId,
        companyId: isAdministration ? _companyId : null,
        noPk: isAdministration ? '' : _noPkController.text.trim(),
        guardStatus: isAdministration ? 'Tetap' : _guardStatus,
      );"""
if text.count(old) != 1:
    raise SystemExit(f'Expected one company admin create block, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
