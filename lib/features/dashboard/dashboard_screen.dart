import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/notifications/notification_service.dart';
import '../admin/admin_screen.dart';
import '../admin/attendance_history_screen.dart';
import '../admin/command_center_screen.dart';
import '../admin/sos_management_screen.dart';
import '../attendance/attendance_screen.dart';
import '../auth/login_screen.dart';
import '../history/clocking_history_screen.dart';
import '../patrol/patrol_screen.dart';
import '../profile/profile_screen.dart';

class DashboardScreen extends StatefulWidget {
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

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final OfflineStore _store = OfflineStore.instance;
  final OfflineSyncService _sync = OfflineSyncService.instance;

  late AppUser _user;
  late int _sessionIntervalMinutes;
  late int _sessionStartMinutes;
  Timer? _sessionTimer;
  Timer? _configTimer;
  StreamSubscription<PushAlert>? _openedPushSubscription;
  String? _lastSessionKey;
  bool _forcingRelogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_changed);
    _sync.addListener(_changed);
    _user = widget.user;
    _sessionIntervalMinutes = widget.user.sessionIntervalMinutes;
    _sessionStartMinutes = widget.user.sessionStartMinutes;
    _lastSessionKey = _sessionKey(DateTime.now());
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkSessionBoundary(),
    );
    _configTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_refreshPatrolConfig()),
    );
    _openedPushSubscription = NotificationService.instance.openedAlerts.listen(
      _openPushTarget,
    );
    unawaited(_refreshPatrolConfig());
    unawaited(_bindNotifications(_user));
    unawaited(_sync.syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPatrolConfig());
      unawaited(_sync.syncNow());
      _checkSessionBoundary();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_changed);
    _sync.removeListener(_changed);
    _sessionTimer?.cancel();
    _configTimer?.cancel();
    _openedPushSubscription?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPatrolConfig() async {
    try {
      final bootstrap = await widget.api.getOfflineBootstrap();
      if (!mounted) return;
      if (_sessionIntervalMinutes != bootstrap.sessionIntervalMinutes ||
          _sessionStartMinutes != bootstrap.sessionStartMinutes) {
        setState(() {
          _sessionIntervalMinutes = bootstrap.sessionIntervalMinutes;
          _sessionStartMinutes = bootstrap.sessionStartMinutes;
        });
        _lastSessionKey = _sessionKey(DateTime.now());
      }
    } catch (_) {
      final cached = _store.cachedBootstrap();
      if (cached != null &&
          mounted &&
          (_sessionIntervalMinutes != cached.sessionIntervalMinutes ||
              _sessionStartMinutes != cached.sessionStartMinutes)) {
        setState(() {
          _sessionIntervalMinutes = cached.sessionIntervalMinutes;
          _sessionStartMinutes = cached.sessionStartMinutes;
        });
      }
    }
  }

  String _sessionKey(DateTime value) {
    final local = value.toUtc().add(const Duration(hours: 8));
    final interval = _sessionIntervalMinutes.clamp(15, 1440);
    final startMinutes = _sessionStartMinutes.clamp(0, 1439);
    final minuteOfDay = local.hour * 60 + local.minute;
    final relativeMinutes = (minuteOfDay - startMinutes + 1440) % 1440;
    final index = relativeMinutes ~/ interval;
    final scheduleDay = minuteOfDay < startMinutes
        ? local.subtract(const Duration(days: 1))
        : local;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${scheduleDay.year}-${two(scheduleDay.month)}-${two(scheduleDay.day)}-$index-$interval-$startMinutes';
  }

  void _checkSessionBoundary() {
    final current = _sessionKey(DateTime.now());
    if (_lastSessionKey == null) {
      _lastSessionKey = current;
      return;
    }
    if (current == _lastSessionKey || _forcingRelogin) return;
    unawaited(_forceReloginForNewSession(current));
  }

  Future<void> _forceReloginForNewSession(String newSessionKey) async {
    if (_forcingRelogin || !mounted) return;
    _forcingRelogin = true;
    final notifications = NotificationService.instance;
    notifications.beginSessionRollover();
    try {
      var token = notifications.currentToken;
      if (token == null || token.isEmpty) {
        await notifications.bindUser(_user);
        token = notifications.currentToken;
      }

      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Auto logout ditangguhkan: push notification belum aktif pada peranti ini.',
              ),
            ),
          );
        }
        return;
      }

      Map<String, dynamic>? handshake;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final result = await widget.api.prepareSessionRollover(token);
          if (result['ready'] == true) {
            handshake = result;
            break;
          }
        } catch (_) {}
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }

      if (handshake == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pemberitahuan sesi baharu belum berjaya dihantar. RimbaKawal akan cuba semula sebelum auto logout.',
              ),
            ),
          );
        }
        return;
      }

      // Only mark the boundary as handled after both notifications were
      // accepted for this exact device.
      _lastSessionKey = newSessionKey;
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await widget.api.logout();
      notifications.detachUserKeepPushToken();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            nfcService: widget.nfcService,
            mockMode: widget.mockMode,
            notice: 'Sesi Rondaan baharu telah bermula. Pemberitahuan telah dihantar dan peranti dilog keluar. Sila log masuk semula untuk meneruskan.',
          ),
        ),
        (_) => false,
      );
    } finally {
      notifications.finishSessionRollover();
      _forcingRelogin = false;
    }
  }

  Future<void> _bindNotifications(AppUser user) async {
    await NotificationService.instance.bindUser(user);
  }

  DateTime? _pushDate(PushAlert alert) {
    for (final key in const ['workDate', 'sessionDate', 'date']) {
      final value = alert.data[key];
      if (value == null || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  void _returnToDashboard() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openPushTarget(PushAlert alert) {
    if (!mounted) return;
    final date = _pushDate(alert);
    switch (alert.kind) {
      case 'session_start':
      case 'patrol_not_started':
      case 'session_ending':
      case 'checkpoint_scanned':
        _openPatrol();
      case 'session_missed':
      case 'session_incomplete':
        _open(
          ClockingHistoryScreen(
            api: widget.api,
            user: _user,
            initialDate: date,
            initialDepartmentId: _user.departmentId,
            initialFilter: 'missed',
          ),
        );
      case 'patrol_completed':
      case 'patrol_ended':
        _open(
          ClockingHistoryScreen(
            api: widget.api,
            user: _user,
            initialDate: date,
            initialDepartmentId: _user.departmentId,
          ),
        );
      case 'attendance_punch':
        _open(AttendanceScreen(api: widget.api, user: _user));
      case 'attendance_review':
        if (_user.canMonitor) {
          _open(AttendanceHistoryScreen(api: widget.api, initialDate: date));
        } else {
          _returnToDashboard();
        }
      case 'incident':
      case 'incident_urgent':
      case 'welfare_attention':
        if (_user.canMonitor) {
          _open(CommandCenterScreen(api: widget.api));
        } else {
          _returnToDashboard();
        }
      case 'sos':
        if (_user.canMonitor) {
          _open(const SosManagementScreen());
        } else {
          _returnToDashboard();
        }
      case 'sos_resolved':
      default:
        _returnToDashboard();
    }
  }

  Future<void> _enableNotifications() async {
    final service = NotificationService.instance;
    if (!service.configured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pemberitahuan belum dikonfigurasi pada pelayan aplikasi.',
          ),
        ),
      );
      return;
    }
    final enabled = await service.requestPermissionAndRegister(_user);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled ? 'Pemberitahuan RimbaKawal telah diaktifkan.' : 'Kebenaran pemberitahuan belum diberikan pada peranti atau pelayar ini.',
        ),
      ),
    );
  }

  Future<void> _logout() async {
    // Best-effort automatic flush before removing the cloud session.
    await _sync.syncNow();
    await NotificationService.instance.unregisterCurrentDevice();
    await widget.api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          nfcService: widget.nfcService,
          mockMode: widget.mockMode,
        ),
      ),
      (_) => false,
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _openPatrol() => _open(
    PatrolScreen(
      user: _user,
      nfcService: widget.nfcService,
      mockMode: widget.mockMode,
      api: widget.api,
    ),
  );

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(user: _user, api: widget.api),
      ),
    );
    await _refreshCurrentUser();
  }

  Future<void> _openAdmin() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(
          api: widget.api,
          nfcService: widget.nfcService,
          mockMode: widget.mockMode,
        ),
      ),
    );
    await _refreshCurrentUser();
  }

  Future<void> _refreshCurrentUser() async {
    try {
      final refreshed = await widget.api.getSession();
      if (refreshed == null || !mounted) return;
      setState(() {
        _user = refreshed;
        _sessionIntervalMinutes = refreshed.sessionIntervalMinutes;
      });
      unawaited(_bindNotifications(refreshed));
      _lastSessionKey = _sessionKey(DateTime.now());
    } catch (_) {
      // Offline mode keeps the locally cached identity and configuration.
    }
  }

  ImageProvider<Object>? _avatar() {
    final picture = _user.profilePicture;
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/') && picture.contains(',')) {
      try {
        return MemoryImage(base64Decode(picture.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(picture);
  }

  String _managementSyncLabel(int pending) {
    if (_sync.isSyncing) return 'PENYEGERAKAN AUTOMATIK • SEDANG DISEGERAKKAN';
    if (pending > 0) return 'PENYEGERAKAN AUTOMATIK • $pending MENUNGGU';
    final last = _sync.lastSyncAt;
    if (last == null) return 'PENYEGERAKAN AUTOMATIK • SEDIA';
    final local = last.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'PENYEGERAKAN AUTOMATIK • ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final image = _avatar();
    final pending = _user.isManagement ? _store.pendingCount(_user.id) : 0;
    final failed = _user.isManagement ? _store.failedCount(_user.id) : 0;
    final online = _sync.isOnline;
    final nfcTestMode = _store.isNfcTestMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RimbaKawal'),
        actions: [
          IconButton(
            tooltip: 'Aktifkan pemberitahuan',
            onPressed: online ? _enableNotifications : null,
            icon: const Icon(Icons.notifications_active_rounded),
          ),
          IconButton(
            tooltip: 'Log keluar',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _refreshCurrentUser();
            await _refreshPatrolConfig();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF251A4F),
                      Color(0xFF151827),
                      Color(0xFF351315),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4834D4).withValues(alpha: 0.16),
                      blurRadius: 36,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: image,
                          child: image == null
                              ? Text(
                                  _user.nama.isEmpty ? '?' : _user.nama[0],
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _user.nama,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_user.jawatanPaparan} • ${_user.jabatan}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusPill(
                          icon: online
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          label: online ? 'DALAM TALIAN' : 'LUAR TALIAN',
                          color: online
                              ? const Color(0xFF55E6C1)
                              : const Color(0xFFFF7675),
                        ),
                        _StatusPill(
                          icon: nfcTestMode
                              ? Icons.science_rounded
                              : Icons.nfc_rounded,
                          label: nfcTestMode ? 'NFC • TEST' : 'NFC • SEBENAR',
                          color: const Color(0xFFA29BFE),
                        ),
                        if (_user.isManagement)
                          _StatusPill(
                            icon: _sync.isSyncing
                                ? Icons.sync_rounded
                                : Icons.cloud_done_outlined,
                            label: _managementSyncLabel(pending),
                            color: const Color(0xFFA29BFE),
                          ),
                        if (_user.isManagement && failed > 0)
                          _StatusPill(
                            icon: Icons.warning_amber_rounded,
                            label: '$failed GAGAL',
                            color: const Color(0xFFFF7675),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Sesi rondaan setiap $_sessionIntervalMinutes minit',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (!online) ...[
                const SizedBox(height: 14),
                Card(
                  color: const Color(0xFF2B1719),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_off_rounded, color: Color(0xFFFF7675)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sambungan internet terputus. Fungsi dalam talian dikunci sementara. Mula Rondaan masih boleh digunakan kerana rekod disimpan pada peranti dan akan disegerakkan semula selepas talian pulih.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                'Operasi',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 760 ? 4 : 2;
                  final items = <_MenuData>[
                    _MenuData(
                      icon: Icons.directions_walk_rounded,
                      title: 'Mula Rondaan',
                      subtitle: 'Imbas checkpoint dan rekod lokasi',
                      onTap: _openPatrol,
                    ),
                    _MenuData(
                      icon: Icons.fingerprint_rounded,
                      title: 'Kehadiran',
                      subtitle: 'Rekod masuk/keluar dengan lokasi dan selfie',
                      onTap: () =>
                          _open(AttendanceScreen(api: widget.api, user: _user)),
                      enabled: online,
                    ),
                    _MenuData(
                      icon: Icons.history_rounded,
                      title: 'Sejarah',
                      subtitle: 'Sesi dan checkpoint',
                      onTap: () => _open(
                        ClockingHistoryScreen(api: widget.api, user: _user),
                      ),
                      enabled: online,
                    ),
                    _MenuData(
                      icon: Icons.person_rounded,
                      title: 'Profil',
                      subtitle: _user.jawatanPaparan,
                      onTap: _openProfile,
                      enabled: online,
                    ),
                    if (_user.isManagement)
                      _MenuData(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Pentadbiran',
                        subtitle: 'Konfigurasi sistem',
                        onTap: _openAdmin,
                        enabled: online,
                      ),
                    if (_user.canMonitor)
                      _MenuData(
                        icon: Icons.monitor_heart_rounded,
                        title: 'Pemantauan',
                        subtitle: 'Pemantauan operasi langsung',
                        onTap: () =>
                            _open(CommandCenterScreen(api: widget.api)),
                        enabled: online,
                      ),
                  ];

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: constraints.maxWidth >= 760
                          ? 1.35
                          : 1.12,
                    ),
                    itemBuilder: (context, index) =>
                        _MenuCard(data: items[index]),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _MenuData {
  const _MenuData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.data});

  final _MenuData data;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: data.enabled ? 1 : 0.42,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.enabled ? data.onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary
                          .withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      data.icon,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  if (!data.enabled)
                    const Icon(Icons.cloud_off_rounded, size: 20),
                ],
              ),
              const Spacer(),
              Text(
                data.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.enabled ? data.subtitle : 'Tidak tersedia tanpa Internet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
