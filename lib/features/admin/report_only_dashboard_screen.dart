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
        builder: (_) => LoginScreen(nfcService: nfcService, mockMode: mockMode),
      ),
      (_) => false,
    );
  }

  void _openReports(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportScreen(api: api, user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = user.companyName.isEmpty ? 'Syarikat belum ditetapkan' : user.companyName;
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
                width: 92,
                height: 92,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user.nama,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.jawatanPaparan} • $company',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FutureBuilder<List<DepartmentRecord>>(
              future: api.getAdminDepartments(),
              builder: (context, snapshot) {
                final count = snapshot.data?.where((item) => item.active).length;
                final subtitle = count == null
                    ? 'Memuatkan senarai sekolah syarikat…'
                    : '$count sekolah di bawah akses syarikat ini';
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openReports(context),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.picture_as_pdf_rounded, size: 48),
                          const SizedBox(height: 14),
                          Text(
                            'Jana Laporan PDF',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(subtitle, textAlign: TextAlign.center),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => _openReports(context),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Pilih Sekolah & Jana Laporan'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_tree_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pentadbiran Syarikat boleh menjana laporan bagi semua sekolah yang dipautkan kepada syarikat yang sama. Fungsi rondaan dan konfigurasi sistem kekal dikunci.',
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
