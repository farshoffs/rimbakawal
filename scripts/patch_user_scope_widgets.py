from pathlib import Path

path = Path('lib/features/admin/user_maintenance_screen.dart')
text = path.read_text(encoding='utf-8')
start = text.index("              Padding(\n                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),\n                child: DropdownButtonFormField<int>(")
end = text.index("              Padding(\n                padding: const EdgeInsets.symmetric(horizontal: 18),", start)
new = """              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: AdminScopeFilterBar(
                  companies: data.companies,
                  departments: data.departments,
                  onChanged: _refresh,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cari Pengguna',
                    hintText: 'Nama, No. IC, No. PK, sekolah atau syarikat',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _roleFilter,
                        decoration: const InputDecoration(labelText: 'Peranan'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua Peranan')),
                          DropdownMenuItem(value: 'administration', child: Text('Pentadbiran Syarikat')),
                          DropdownMenuItem(value: 'supervisor', child: Text('Penyelia')),
                          DropdownMenuItem(value: 'patrol', child: Text('Pengawal Rondaan')),
                        ],
                        onChanged: (value) => setState(() => _roleFilter = value ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Status Akaun'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua Status')),
                          DropdownMenuItem(value: 'active', child: Text('Aktif')),
                          DropdownMenuItem(value: 'blocked', child: Text('Disekat')),
                        ],
                        onChanged: (value) => setState(() => _statusFilter = value ?? 'all'),
                      ),
                    ),
                  ],
                ),
              ),
"""
path.write_text(text[:start] + new + text[end:], encoding='utf-8')
