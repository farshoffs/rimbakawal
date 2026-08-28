import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';

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
    _future = widget.api.getAdminUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
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
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(user.nama.isEmpty ? '?' : user.nama[0]),
                  ),
                  title: Text(user.nama),
                  subtitle: Text(
                    '${user.noKadPengenalan}\n${user.jawatan} • ${user.jabatan}',
                  ),
                  isThreeLine: true,
                  trailing: user.isManagement
                      ? const Icon(Icons.admin_panel_settings_rounded)
                      : const Icon(Icons.shield_outlined),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
