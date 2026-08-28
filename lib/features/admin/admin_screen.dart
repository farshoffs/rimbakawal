import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import 'department_maintenance_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<List<AppUser>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _future = widget.api.getAdminUsers());
  }

  Future<void> _openDepartmentMaintenance() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DepartmentMaintenanceScreen(api: widget.api),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _changeDepartment(AppUser user) async {
    try {
      final departments = await widget.api.getAdminDepartments();
      if (!mounted) return;
      final activeDepartments = departments.where((item) => item.active).toList();
      int? selected = user.departmentId;
      final departmentId = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Tetapkan sekolah — ${user.nama}'),
          content: SizedBox(
            width: 420,
            child: DropdownMenu<int>(
              initialSelection: selected,
              width: 380,
              label: const Text('Jabatan / Sekolah'),
              dropdownMenuEntries: activeDepartments
                  .map(
                    (department) => DropdownMenuEntry<int>(
                      value: department.id,
                      label: department.name,
                    ),
                  )
                  .toList(),
              onSelected: (value) => selected = value,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
      if (departmentId == null) return;
      await widget.api.updateUserDepartment(user.id, departmentId);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jabatan/sekolah pengguna dikemas kini.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
              ),
            );
          }
          final users = snapshot.data ?? const <AppUser>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openDepartmentMaintenance,
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(
                      children: [
                        CircleAvatar(
                          child: Icon(Icons.account_tree_rounded),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jabatan / Sekolah, Checkpoint & Sesi',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Tambah atau selenggara sekolah, kadar sesi rondaan, checkpoint dan NFC UID.',
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Pengguna (${users.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              ...users.map(
                (user) => Card(
                  child: ListTile(
                    onTap: () => _changeDepartment(user),
                    leading: CircleAvatar(
                      child: Text(user.nama.isEmpty ? '?' : user.nama[0]),
                    ),
                    title: Text(user.nama),
                    subtitle: Text(
                      '${user.noKadPengenalan}\n${user.jawatan} • ${user.jabatan}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_location_alt_rounded),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
