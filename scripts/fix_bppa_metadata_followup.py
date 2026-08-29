from pathlib import Path


def patch(path, old, new):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f'missing marker: {path}')
    p.write_text(s.replace(old, new, 1))

patch(
    'lib/features/admin/user_maintenance_screen.dart',
    "              const SizedBox(height: 12),\n              TextField(\n                controller: _noPkController,\n                decoration: const InputDecoration(\n                  labelText: 'No. PK',\n                  prefixIcon: Icon(Icons.numbers_rounded),\n                ),\n              ),\n              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n                initialValue: _jawatan,\n",
    "              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n                initialValue: _jawatan,\n",
)

add_marker = "              TextField(\n                controller: _icController,\n                keyboardType: TextInputType.number,\n                maxLength: 12,\n                decoration: const InputDecoration(\n                  labelText: 'No. Kad Pengenalan',\n                  prefixIcon: Icon(Icons.badge_outlined),\n                ),\n              ),\n              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n"
add_replacement = "              TextField(\n                controller: _icController,\n                keyboardType: TextInputType.number,\n                maxLength: 12,\n                decoration: const InputDecoration(\n                  labelText: 'No. Kad Pengenalan',\n                  prefixIcon: Icon(Icons.badge_outlined),\n                ),\n              ),\n              const SizedBox(height: 12),\n              TextField(\n                controller: _noPkController,\n                decoration: const InputDecoration(\n                  labelText: 'No. PK',\n                  prefixIcon: Icon(Icons.numbers_rounded),\n                  helperText: 'Nombor pengawal untuk borang BPPA PKK 2.',\n                ),\n              ),\n              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n"
patch('lib/features/admin/user_maintenance_screen.dart', add_marker, add_replacement)

patch(
    'worker/app.js',
    "async function getUserById(env, id) {\n  return env.DB.prepare(\n    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,\n",
    "async function getUserById(env, id) {\n  return env.DB.prepare(\n    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan, u.profile_picture,\n",
)
