import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../auth/login_screen.dart';
import 'report_screen.dart';

class ReportOnlyDashboardScreen extends StatelessWidget {
  const ReportOnlyDashboardScreen({
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZPatrol'),
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Center(
              child: Image.asset(
                'assets/branding/zpatrol_icon.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              user.nama,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              '${user.jawatanPaparan} • ${user.jabatan}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, size: 42),
                    const SizedBox(height: 14),
                    Text(
                      'Laporan PDF',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Akaun Pentadbiran Syarikat dikhaskan untuk menjana dan memuat turun laporan PDF bagi lokasi sendiri.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReportScreen(api: api),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Buka Laporan PDF'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Akses rondaan, kehadiran, pemantauan, pengurusan pengguna, tetapan checkpoint dan fungsi pentadbiran sistem tidak diberikan kepada tahap ini.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
