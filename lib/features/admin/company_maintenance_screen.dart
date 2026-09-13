import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class CompanyMaintenanceScreen extends StatefulWidget {
  const CompanyMaintenanceScreen({required this.api, super.key});
  final ApiService api;

  @override
  State<CompanyMaintenanceScreen> createState() =>
      _CompanyMaintenanceScreenState();
}

class _CompanyMaintenanceScreenState extends State<CompanyMaintenanceScreen> {
  late Future<List<CompanyRecord>> _future;
  int _refreshKey = 0;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'active';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _refreshKey++;
      _future = widget.api.getAdminCompanies();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _open([CompanyRecord? company]) async {
    final controller = TextEditingController(text: company?.name ?? '');
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(company == null ? 'Cipta Syarikat' : 'Edit Syarikat'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Nama Syarikat',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                ),
                if (company != null) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Status aktif diurus melalui Arkib/Pulihkan supaya sekolah dan pengguna di bawah syarikat boleh dipulihkan semula dengan selamat.',
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.length < 2) {
                  setDialogState(
                    () => error = 'Masukkan nama Syarikat yang sah.',
                  );
                  return;
                }
                try {
                  if (company == null) {
                    await widget.api.createCompany(name);
                  } else {
                    await widget.api.updateCompany(
                      CompanyRecord(
                        id: company.id,
                        name: name,
                        active: company.active,
                        schoolCount: company.schoolCount,
                        administrationCount: company.administrationCount,
                      ),
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } catch (e) {
                  setDialogState(() => error = e.toString());
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (changed == true && mounted) _reload();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _archiveCompany(CompanyRecord company) async {
    final confirmed = await _confirm(
      title: 'Arkib Syarikat?',
      message:
          'Syarikat ${company.name} akan diarkibkan bersama sekolah, checkpoint dan akaun berkaitan. Data sejarah tidak dipadam dan boleh dipulihkan semula.',
      action: 'Arkib',
    );
    if (!confirmed) return;
    try {
      await widget.api.deleteCompany(company.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${company.name} telah diarkibkan.'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              await widget.api.restoreCompany(company.id);
              if (mounted) _reload();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _restoreCompany(CompanyRecord company) async {
    try {
      await widget.api.restoreCompany(company.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${company.name} berjaya dipulihkan.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _archiveSchool(DepartmentRecord school) async {
    final confirmed = await _confirm(
      title: 'Arkib Sekolah?',
      message:
          '${school.name} akan diarkibkan. Pengguna dan checkpoint sekolah ini dinyahaktifkan sementara, tetapi semua sejarah kekal disimpan untuk audit dan laporan.',
      action: 'Arkib',
    );
    if (!confirmed) return;
    try {
      await widget.api.deleteDepartment(school.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${school.name} telah diarkibkan.'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              await widget.api.restoreDepartment(school.id);
              if (mounted) _reload();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _restoreSchool(DepartmentRecord school) async {
    try {
      await widget.api.restoreDepartment(school.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${school.name} berjaya dipulihkan.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengurusan Syarikat')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Cipta Syarikat'),
      ),
      body: FutureBuilder<List<CompanyRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final companies = snapshot.data ?? const <CompanyRecord>[];
          final query = _searchController.text.trim().toLowerCase();
          final visibleCompanies = companies.where((company) {
            final matchesStatus =
                _statusFilter == 'all' ||
                (_statusFilter == 'active' ? company.active : !company.active);
            final matchesQuery =
                query.isEmpty || company.name.toLowerCase().contains(query);
            return matchesStatus && matchesQuery;
          }).toList();
          if (companies.isEmpty) {
            return const Center(child: Text('Belum ada Syarikat.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: visibleCompanies.length + 1,
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
                      const Text(
                        'Tiada syarikat untuk penapis atau carian ini.',
                      ),
                    ],
                  ],
                );
              }
              final company = visibleCompanies[index - 1];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  key: ValueKey('${company.id}-$_refreshKey'),
                  leading: CircleAvatar(
                    child: Icon(
                      company.active
                          ? Icons.business_rounded
                          : Icons.inventory_2_outlined,
                    ),
                  ),
                  title: Text(
                    company.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${company.schoolCount} Sekolah • ${company.administrationCount} Pentadbiran'
                    '${company.active ? '' : ' • DIARKIBKAN'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _open(company);
                        case 'archive':
                          _archiveCompany(company);
                        case 'restore':
                          _restoreCompany(company);
                      }
                    },
                    itemBuilder: (_) => [
                      if (company.active)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_rounded),
                            title: Text('Edit'),
                          ),
                        ),
                      if (company.active)
                        const PopupMenuItem(
                          value: 'archive',
                          child: ListTile(
                            leading: Icon(Icons.archive_rounded),
                            title: Text('Arkib Syarikat'),
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'restore',
                          child: ListTile(
                            leading: Icon(Icons.restore_rounded),
                            title: Text('Pulihkan Syarikat'),
                          ),
                        ),
                    ],
                  ),
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: FutureBuilder<List<DepartmentRecord>>(
                        future: widget.api.getAdminDepartments(
                          companyId: company.id,
                          includeArchived: true,
                        ),
                        builder: (context, schoolSnapshot) {
                          if (schoolSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (schoolSnapshot.hasError) {
                            return Text(schoolSnapshot.error.toString());
                          }
                          final schools =
                              schoolSnapshot.data ?? const <DepartmentRecord>[];
                          if (schools.isEmpty) {
                            return const ListTile(
                              leading: Icon(Icons.school_outlined),
                              title: Text(
                                'Belum ada sekolah di bawah syarikat ini.',
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Sekolah di bawah ${company.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final school in schools)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    school.active
                                        ? Icons.school_rounded
                                        : Icons.inventory_2_outlined,
                                  ),
                                  title: Text(
                                    school.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${school.zone.isEmpty ? 'Zon -' : 'Zon ${school.zone}'} • '
                                    '${school.checkpointCount} checkpoint'
                                    '${school.active ? '' : ' • DIARKIBKAN'}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: school.active
                                        ? 'Arkib Sekolah'
                                        : 'Pulihkan Sekolah',
                                    onPressed: company.active
                                        ? () => school.active
                                              ? _archiveSchool(school)
                                              : _restoreSchool(school)
                                        : null,
                                    icon: Icon(
                                      school.active
                                          ? Icons.archive_outlined
                                          : Icons.restore_rounded,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
