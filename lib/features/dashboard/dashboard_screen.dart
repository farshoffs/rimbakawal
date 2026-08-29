import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/notifications/notification_service.dart';
import '../admin/admin_screen.dart';
import '../admin/command_center_screen.dart';
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
  final AudioPlayer _alarmPlayer = AudioPlayer();

  late AppUser _user;
  late int _sessionIntervalMinutes;
  late int _sessionStartMinutes;
  Timer? _sessionTimer;
  Timer? _configTimer;
  String? _lastSessionKey;
  bool _alarmShowing = false;
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
    unawaited(_refreshPatrolConfig());
    unawaited(NotificationService.instance.bindUser(_user));
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
    _alarmPlayer.dispose();
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
      if (cached != null && mounted &&
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
    if (current == _lastSessionKey) return;
    _lastSessionKey = current;
    unawaited(_forceReloginForNewSession());
  }

  Future<void> _forceReloginForNewSession() async {
    if (_forcingRelogin || !mounted) return;
    _forcingRelogin = true;
    try {
      await _alarmPlayer.stop();
      try {
        await NotificationService.instance.unregisterCurrentDevice();
      } catch (_) {}
      await widget.api.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            nfcService: widget.nfcService,
            mockMode: widget.mockMode,
            notice: 'Sesi Rondaan baharu telah bermula. Sila log masuk semula untuk meneruskan.',
          ),
        ),
        (_) => false,
      );
    } finally {
      _forcingRelogin = false;
    }
  }

  Future<void> _playAlarm() async {
    try {
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.setVolume(1);
      await _alarmPlayer.play(AssetSource('audio/patrol_alarm.wav'));
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _showSessionAlarm({bool testMode = false}) async {
    if (!mounted || _alarmShowing) return;
    _alarmShowing = true;
    try {
      await _playAlarm();
      if (!mounted) return;
      final startPatrol = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: const Color(0xFF080910),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF331315),
                          Color(0xFF171827),
                          Color(0xFF251A4F),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          size: 92,
                          color: Color(0xFFFF6B6B),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          testMode ? 'UJIAN PENGGERA' : 'SESI RONDAAN BARU',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _user.jabatan,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          testMode
                              ? 'Ini ialah ujian paparan dan bunyi penggera RimbaKawal.'
                              : 'Sesi baharu telah bermula. Lengkapkan semua checkpoint dalam tempoh sesi. Rekod rondaan akan disimpan pada peranti sebelum disegerakkan.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 26),
                        if (!testMode)
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).pop(true),
                            icon: const Icon(Icons.directions_walk_rounded),
                            label: const Text('MULA RONDAAN'),
                          ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Tutup penggera'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (startPatrol == true && mounted) _openPatrol();
    } finally {
      await _alarmPlayer.stop();
      _alarmShowing = false;
    }
  }

  Future<Map<String, dynamic>?> _lastLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _triggerSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rekod SOS?'),
        content: const Text(
          'SOS akan disimpan pada telefon dahulu dan dihantar secara automatik apabila ada internet. Ia tidak menghubungi talian kecemasan secara automatik.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('REKOD SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _store.queueEvent(
      userId: _user.id,
      type: 'sos',
      location: await _lastLocation(),
      payload: const {'note': 'SOS dicetuskan dari dashboard'},
    );
    unawaited(_sync.syncNow());
    await SystemSound.play(SystemSoundType.alert);
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      pageBuilder: (context, _, _) => Scaffold(
        backgroundColor: const Color(0xFF210608),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sos_rounded,
                    size: 110,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'SOS DISIMPAN',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Rekod SOS telah disimpan pada peranti dan akan dihantar secara automatik apabila sambungan tersedia.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.alarm_rounded)),
                title: const Text('Uji Penggera'),
                subtitle: const Text('Uji paparan penuh dan bunyi penggera.'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_showSessionAlarm(testMode: true));
                },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.sos_rounded)),
                title: const Text('SOS'),
                subtitle: const Text('Simpan SOS pada telefon dahulu.'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_triggerSos());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enableNotifications() async {
    final service = NotificationService.instance;
    if (!service.configured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pemberitahuan belum dikonfigurasi pada pelayan aplikasi.'),
        ),
      );
      return;
    }
    final enabled = await service.requestPermissionAndRegister(_user);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Pemberitahuan RimbaKawal telah diaktifkan.'
              : 'Kebenaran pemberitahuan belum diberikan pada peranti atau pelayar ini.',
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
      unawaited(NotificationService.instance.bindUser(refreshed));
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('RimbaKawal'),
        actions: [
          IconButton(
            tooltip: 'Aktifkan pemberitahuan',
            onPressed: _enableNotifications,
            icon: const Icon(Icons.notifications_active_rounded),
          ),
          IconButton(
            tooltip: 'Penggera / SOS',
            onPressed: _showQuickActions,
            icon: const Icon(Icons.crisis_alert_rounded),
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
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text('${_user.jawatanPaparan} • ${_user.jabatan}'),
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
                        const _StatusPill(
                          icon: Icons.offline_bolt_rounded,
                          label: 'SEDIA LUAR TALIAN',
                          color: Color(0xFF74B9FF),
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
              const SizedBox(height: 22),
              Text(
                'Operasi',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
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
                      icon: Icons.history_rounded,
                      title: 'Sejarah',
                      subtitle: 'Sesi dan checkpoint',
                      onTap: () => _open(ClockingHistoryScreen(api: widget.api)),
                    ),
                    _MenuData(
                      icon: Icons.person_rounded,
                      title: 'Profil',
                      subtitle: _user.jawatanPaparan,
                      onTap: _openProfile,
                    ),
                    if (_user.isManagement)
                      _MenuData(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Pentadbiran',
                        subtitle: 'Konfigurasi sistem',
                        onTap: _openAdmin,
                      ),
                    if (_user.canMonitor)
                      _MenuData(
                        icon: Icons.monitor_heart_rounded,
                        title: 'Pemantauan',
                        subtitle: 'Pemantauan operasi langsung',
                        onTap: () => _open(CommandCenterScreen(api: widget.api)),
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
                      childAspectRatio:
                          constraints.maxWidth >= 760 ? 1.35 : 1.12,
                    ),
                    itemBuilder: (context, index) => _MenuCard(data: items[index]),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.data});

  final _MenuData data;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: data.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary
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
                Text(
                  data.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
}
