import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';
import '../history/clocking_history_screen.dart';
import '../patrol/patrol_screen.dart';
import '../profile/profile_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.user,
    required this.api,
    required this.nfcService,
    required this.mockMode,
    super.key,
  });

  final AppUser user;
  final ApiService api;
  final NfcService nfcService;
  final bool mockMode;

  Future<void> _logout(BuildContext context) async {
    await api.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          nfcService: nfcService,
          mockMode: mockMode,
        ),
      ),
      (_) => false,
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RimbaKawal'),
        actions: [
          IconButton(
            tooltip: 'Log keluar',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    _Avatar(user: user, radius: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.nama,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text('${user.jawatan} • ${user.jabatan}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 700 ? 4 : 2;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.05,
                  children: [
                    _MenuCard(
                      icon: Icons.nfc_rounded,
                      title: 'Scan NFC',
                      onTap: () => _open(
                        context,
                        PatrolScreen(
                          nfcService: nfcService,
                          mockMode: mockMode,
                          api: api,
                        ),
                      ),
                    ),
                    _MenuCard(
                      icon: Icons.history_rounded,
                      title: 'Clocking History',
                      onTap: () => _open(
                        context,
                        ClockingHistoryScreen(api: api),
                      ),
                    ),
                    _MenuCard(
                      icon: Icons.person_rounded,
                      title: 'Profile',
                      onTap: () => _open(
                        context,
                        ProfileScreen(user: user),
                      ),
                    ),
                    if (user.isManagement)
                      _MenuCard(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Admin',
                        onTap: () => _open(
                          context,
                          AdminScreen(api: api),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 42, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.radius});

  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final picture = user.profilePicture;
    if (picture != null && picture.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(picture));
    }
    final initial = user.nama.isEmpty ? '?' : user.nama[0];
    return CircleAvatar(radius: radius, child: Text(initial));
  }
}
