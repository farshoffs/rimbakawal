from pathlib import Path
p=Path('lib/features/admin/company_maintenance_screen.dart')
t=p.read_text(encoding='utf-8')

def one(a,b,label):
    global t
    n=t.count(a)
    if n!=1: raise SystemExit(f'{label}: {n}')
    t=t.replace(a,b,1)

one("""  late Future<List<CompanyRecord>> _future;
  int _refreshKey = 0;""","""  late Future<List<CompanyRecord>> _future;
  int _refreshKey = 0;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'active';""",'state')
one("""  void _reload() {
    setState(() {
      _refreshKey++;
      _future = widget.api.getAdminCompanies();
    });
  }""","""  void _reload() {
    setState(() {
      _refreshKey++;
      _future = widget.api.getAdminCompanies();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }""",'dispose')
one("""          final companies = snapshot.data ?? const <CompanyRecord>[];
          if (companies.isEmpty) {""","""          final companies = snapshot.data ?? const <CompanyRecord>[];
          final query = _searchController.text.trim().toLowerCase();
          final visibleCompanies = companies.where((company) {
            final matchesStatus = _statusFilter == 'all' ||
                (_statusFilter == 'active' ? company.active : !company.active);
            final matchesQuery = query.isEmpty || company.name.toLowerCase().contains(query);
            return matchesStatus && matchesQuery;
          }).toList();
          if (companies.isEmpty) {""",'filter derive')
one("""            itemCount: companies.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final company = companies[index];""","""            itemCount: visibleCompanies.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              if (index == 0) {
                return Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Cari Syarikat',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'active', label: Text('Aktif')),
                        ButtonSegment(value: 'archived', label: Text('Arkib')),
                        ButtonSegment(value: 'all', label: Text('Semua')),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (value) {
                        if (value.isNotEmpty) {
                          setState(() => _statusFilter = value.first);
                        }
                      },
                    ),
                    if (visibleCompanies.isEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('Tiada syarikat untuk penapis atau carian ini.'),
                    ],
                  ],
                );
              }
              final company = visibleCompanies[index - 1];""",'list header')
# Normalize an existing single-line mounted guard so flutter analyze stays clean.
one("""                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);""","""                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }""",'mounted guard')
p.write_text(t,encoding='utf-8')
