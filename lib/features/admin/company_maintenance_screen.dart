import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class CompanyMaintenanceScreen extends StatefulWidget {
  const CompanyMaintenanceScreen({required this.api, super.key});
  final ApiService api;

  @override
  State<CompanyMaintenanceScreen> createState() => _CompanyMaintenanceScreenState();
}

class _CompanyMaintenanceScreenState extends State<CompanyMaintenanceScreen> {
  late Future<List<CompanyRecord>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = widget.api.getAdminCompanies());

  Future<void> _open([CompanyRecord? company]) async {
    final controller = TextEditingController(text: company?.name ?? '');
    var active = company?.active ?? true;
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
                if (company != null)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Syarikat aktif'),
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                  ),
                if (error != null)
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                  setDialogState(() => error = 'Masukkan nama Syarikat yang sah.');
                  return;
                }
                try {
                  if (company == null) {
                    await widget.api.createCompany(name);
                  } else {
                    await widget.api.updateCompany(CompanyRecord(
                      id: company.id,
                      name: name,
                      active: active,
                      schoolCount: company.schoolCount,
                      administrationCount: company.administrationCount,
                    ));
                  }
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
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
          if (companies.isEmpty) {
            return const Center(child: Text('Belum ada Syarikat.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: companies.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final company = companies[index];
              return Card(
                child: ListTile(
                  onTap: () => _open(company),
                  leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
                  title: Text(company.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                    '${company.schoolCount} Sekolah • ${company.administrationCount} Pentadbiran'
                    '${company.active ? '' : ' • TIDAK AKTIF'}',
                  ),
                  trailing: const Icon(Icons.edit_rounded),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
