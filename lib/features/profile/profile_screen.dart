import 'package:flutter/material.dart';

import '../../core/api/app_user.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.user, super.key});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final picture = user.profilePicture;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 54,
              backgroundImage: picture != null && picture.isNotEmpty
                  ? NetworkImage(picture)
                  : null,
              child: picture == null || picture.isEmpty
                  ? Text(
                      user.nama.isEmpty ? '?' : user.nama[0],
                      style: const TextStyle(fontSize: 36),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          _InfoTile(label: 'Nama', value: user.nama),
          _InfoTile(label: 'No. Kad Pengenalan', value: user.noKadPengenalan),
          _InfoTile(label: 'Jawatan', value: user.jawatan),
          _InfoTile(label: 'Jabatan', value: user.jabatan),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    );
  }
}
