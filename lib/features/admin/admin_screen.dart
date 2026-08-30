import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/nfc/nfc_service.dart';
import 'attendance_history_screen.dart';
import 'command_center_screen.dart';
import 'department_maintenance_screen.dart';
import 'live_patrol_map_screen.dart';
import 'report_screen.dart';
import 'sos_management_screen.dart';
import 'user_maintenance_screen.dart';
import '../settings/nfc_settings_screen.dart';

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
        padding: const EdgeInsets.all(16),
        children: [
          _AdminMenuCard(
            icon: Icons.map_rounded,
            title: 'Peta Rondaan Langsung',
            subtitle: 'Lihat kedudukan semasa peronda yang sedang meronda.',
            onTap: () => _open(context, LivePatrolMapScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.monitor_heart_rounded,
            title: 'Pusat Pemantauan',
            subtitle:
                'Pantau rondaan, sesi terlepas, SOS dan insiden secara langsung.',
            onTap: () => _open(context, CommandCenterScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.fingerprint_rounded,
            title: 'Sejarah Kehadiran',
            subtitle:
                'Semak punch masuk/keluar, geofence dan detail pengesahan wajah.',
            onTap: () => _open(context, AttendanceHistoryScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.sos_rounded,
            title: 'Pengurusan SOS',
            subtitle:
                'Lihat SOS aktif dan tandakan selesai bersama catatan audit.',
            onTap: () => _open(context, const SosManagementScreen()),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.people_alt_rounded,
            title: 'Senarai Pengguna',
            subtitle: 'Tambah pengguna dan tetapkan Jabatan.',
            onTap: () => _open(context, UserMaintenanceScreen(api: api)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.account_tree_rounded,
            title: 'Jabatan dan Checkpoint',
            subtitle:
                'Selenggara Jabatan, kadar sesi dan checkpoint dalam satu skrin.',
            onTap: () => _open(
              context,
              DepartmentMaintenanceScreen(
                api: api,
                nfcService: nfcService,
                mockMode: mockMode,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.nfc_rounded,
            title: 'Tetapan NFC',
            subtitle: 'Tukar antara Mod Test NFC dan Mod Scan NFC Sebenar.',
            onTap: () => _open(context, NfcSettingsScreen(mockMode: mockMode)),
          ),
          const SizedBox(height: 10),
          _AdminMenuCard(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Laporan',
            subtitle: 'Jana dan simpan laporan rondaan dalam PDF.',
            onTap: () => _open(context, ReportScreen(api: api)),
          ),
        ],
      ),
    );
  }
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
