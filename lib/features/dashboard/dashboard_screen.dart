import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../admin/admin_screen.dart';
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
  late AppUser _user;
  late int _sessionIntervalMinutes;
  final AudioPlayer _alarmPlayer = AudioPlayer();
  Timer? _sessionTimer;
  Timer? _configTimer;
  String? _lastSessionKey;
  bool _alarmShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = widget.user;
    _sessionIntervalMinutes = widget.user.sessionIntervalMinutes;
    _lastSessionKey = _sessionKey(DateTime.now());
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkSessionBoundary(),
    );
    _configTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshPatrolConfig(),
    );
    _refreshPatrolConfig();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPatrolConfig();
      _checkSessionBoundary();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _configTimer?.cancel();
    _alarmPlayer.dispose();
    super.dispose();
  }

  Future<void> _refreshPatrolConfig() async {
    try {
      final config = await widget.api.getPatrolConfig();
      if (!mounted) return;
      if (_sessionIntervalMinutes != config.sessionIntervalMinutes) {
        setState(() => _sessionIntervalMinutes = config.sessionIntervalMinutes);
        _lastSessionKey = _sessionKey(DateTime.now());
      }
    } catch (_) {}
  }

  String _sessionKey(DateTime value) {
    final local = value.toLocal();
    final interval = _sessionIntervalMinutes <= 0 ? 120 : _sessionIntervalMinutes;
    final minuteOfDay = local.hour * 60 + local.minute;
    final index = minuteOfDay ~/ interval;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}-$index-$interval';
  }

  void _checkSessionBoundary() {
    if (_user.isManagement) return;
    final current = _sessionKey(DateTime.now());
    if (_lastSessionKey == null) {
      _lastSessionKey = current;
      return;
    }
    if (current == _lastSessionKey) return;
    _lastSessionKey = current;
    _showSessionAlarm();
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
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: const Color(0xFF09090F),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        size: 108,
                        color: Color(0xFFC0392B),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        testMode ? 'UJIAN ALARM' : 'SESI RONDAAN BARU',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _user.jabatan,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        testMode
                            ? 'Ini ialah ujian paparan dan bunyi alarm RimbaKawal.'
                            : 'Sesi baharu telah bermula. Kadar rondaan Jabatan ini ialah setiap $_sessionIntervalMinutes minit. Sila lengkapkan semua checkpoint.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, height: 1.5),
                      ),
                      const SizedBox(height: 32),
                      if (!testMode)
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.nfc_rounded),
                          label: const Text('MULA RONDAAN'),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Tutup alarm'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (startPatrol == true && mounted) {
        _open(
          PatrolScreen(
            nfcService: widget.nfcService,
            mockMode: widget.mockMode,
            api: widget.api,
          ),
        );
      }
    } finally {
      await _alarmPlayer.stop();
      _alarmShowing = false;
    }
  }

  Future<void> _triggerSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aktifkan SOS?'),
        content: const Text(
          'SOS akan direkod dalam RimbaKawal dan dimasukkan ke laporan Admin. Ia tidak menghubungi talian kecemasan secara automatik.',
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
    try {
      await widget.api.createSos(note: 'SOS dicetuskan dari dashboard');
      if (!mounted) return;
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
                    const Icon(Icons.sos_rounded, size: 110, color: Colors.redAccent),
                    const SizedBox(height: 20),
                    Text(
                      'SOS DIREKODKAN',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Event ini telah direkod dalam RimbaKawal. Jika ini kecemasan sebenar, hubungi pihak bertanggungjawab atau perkhidmatan kecemasan secara terus.',
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showQuickActions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.alarm_rounded)),
                title: const Text('Test Alarm'),
                subtitle: const Text('Uji paparan penuh dan bunyi alarm.'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showSessionAlarm(testMode: true);
                },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.sos_rounded)),
                title: const Text('SOS'),
                subtitle: const Text('Rekod event SOS ke sistem.'),
                onTap: () {
                  Navigator.of(context).pop();
                  _triggerSos();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
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
      _lastSessionKey = _sessionKey(DateTime.now());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RimbaKawal'),
        actions: [
          IconButton(
            tooltip: 'Alarm / SOS',
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
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    _Avatar(user: _user, radius: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _user.nama,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text('${_user.jawatan} • ${_user.jabatan}'),
                          const SizedBox(height: 4),
                          Text(
                            'Sesi rondaan: setiap $_sessionIntervalMinutes minit',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                        PatrolScreen(
                          nfcService: widget.nfcService,
                          mockMode: widget.mockMode,
                          api: widget.api,
                        ),
                      ),
                    ),
                    _MenuCard(
                      icon: Icons.history_rounded,
                      title: 'Clocking History',
                      onTap: () => _open(
                        ClockingHistoryScreen(api: widget.api),
                      ),
                    ),
                    _MenuCard(
                      icon: Icons.person_rounded,
                      title: 'Profile',
                      onTap: _openProfile,
                    ),
                    if (_user.isManagement)
                      _MenuCard(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Admin',
                        onTap: _openAdmin,
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
  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) return MemoryImage(base64Decode(picture.substring(comma + 1)));
    }
    return NetworkImage(picture);
  }
  @override
  Widget build(BuildContext context) {
    final image = _imageProvider(user.profilePicture);
    final initial = user.nama.isEmpty ? '?' : user.nama[0];
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      child: image == null ? Text(initial) : null,
    );
  }
}
