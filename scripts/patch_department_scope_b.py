from pathlib import Path
p=Path('lib/features/admin/department_maintenance_screen.dart')
t=p.read_text(encoding='utf-8')
old="""            itemCount: departments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final department = departments[index];"""
new="""            itemCount: visibleDepartments.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    AdminScopeFilterBar(
                      companies: companies,
                      departments: departments,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Cari Sekolah',
                        hintText: 'Nama sekolah, syarikat atau zon',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    if (visibleDepartments.isEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('Tiada sekolah untuk skop atau carian ini.'),
                    ],
                  ],
                );
              }
              final department = visibleDepartments[index - 1];"""
if t.count(old)!=1: raise SystemExit(f'list block {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
