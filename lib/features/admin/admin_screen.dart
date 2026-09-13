import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/nfc/nfc_service.dart';
import '../settings/nfc_settings_screen.dart';
import 'attendance_history_screen.dart';
import 'command_center_screen.dart';
import 'company_maintenance_screen.dart';
import 'department_maintenance_screen.dart';
import 'live_patrol_map_screen.dart';
import 'report_screen.dart';
import 'sos_management_screen.dart';
import 'user_maintenance_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({
    required this.api,
    required this.nfcService,
    required this.mockMode,
    super.key,
  });

  final ApiService api;
  final NfcService nfcService;
  final bool mockMode;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pentadbiran')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          const _AdminSectionTitle(
            icon: Icons.monitor_heart_rounded,
            title: 'Operasi',
            subtitle: 'Pantauan semasa, kehadiran dan keselamatan',
          ),
          _AdminMenuCard(
            icon: Icons.monitor_heart_rounded,
            title: 'Pusat Pemantauan',
            subtitle:
                'Pantau rondaan, sesi terlepas, SOS dan insiden mengikut syarikat atau sekolah.',
            onTap: () => _open(context, CommandCenterScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.map_rounded,
            title: 'Peta Rondaan Langsung',
            subtitle:
                'Lihat kedudukan peronda dan tapis mengikut syarikat atau sekolah.',
            onTap: () => _open(context, LivePatrolMapScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.fingerprint_rounded,
            title: 'Sejarah Kehadiran',
            subtitle:
                'Semak punch, geofence dan pengesahan wajah mengikut skop organisasi.',
            onTap: () => _open(context, AttendanceHistoryScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.sos_rounded,
            title: 'Pengurusan SOS',
            subtitle: 'Lihat dan selesaikan SOS dengan catatan audit.',
            onTap: () => _open(context, const SosManagementScreen()),
          ),
          const SizedBox(height: 24),
          const _AdminSectionTitle(
            icon: Icons.account_tree_rounded,
            title: 'Organisasi',
            subtitle: 'Struktur Syarikat → Sekolah → Pengguna → Checkpoint',
          ),
          _AdminMenuCard(
            icon: Icons.business_rounded,
            title: 'Pengurusan Syarikat',
            subtitle:
                'Urus syarikat induk dan sekolah di bawah setiap syarikat.',
            onTap: () => _open(context, CompanyMaintenanceScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.people_alt_rounded,
            title: 'Pengguna Syarikat',
            subtitle:
                'Cari, tapis, tambah, pindah assignment dan urus status akaun.',
            onTap: () => _open(context, UserMaintenanceScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.school_rounded,
            title: 'Sekolah dan Checkpoint',
            subtitle:
                'Selenggara sekolah, syarikat induk, sesi, kawasan kehadiran dan checkpoint.',
            onTap: () => _open(
              context,
              DepartmentMaintenanceScreen(
                api: api,
                nfcService: nfcService,
                mockMode: mockMode,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _AdminSectionTitle(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Laporan',
            subtitle: 'Dokumen operasi dan PKK',
          ),
          _AdminMenuCard(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Laporan PKK',
            subtitle:
                'Pilih syarikat dan sekolah sebelum menjana PKK 2, PKK 3 dan PKK 4.',
            onTap: () => _open(context, ReportScreen(api: api)),
          ),
          const SizedBox(height: 24),
          const _AdminSectionTitle(
            icon: Icons.settings_rounded,
            title: 'Sistem',
            subtitle: 'Tetapan teknikal peranti',
          ),
          _AdminMenuCard(
            icon: Icons.nfc_rounded,
            title: 'Tetapan NFC',
            subtitle: 'Tukar antara Mod Test NFC dan Mod Scan NFC Sebenar.',
            onTap: () => _open(context, NfcSettingsScreen(mockMode: mockMode)),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionTitle extends StatelessWidget {
  const _AdminSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AdminMenuCard extends StatelessWidget {
  const _AdminMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(radius: 26, child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
