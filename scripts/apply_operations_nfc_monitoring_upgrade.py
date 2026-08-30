from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f'Expected block not found in {path}: {old[:120]!r}')
    text = text.replace(old, new, 1)
    write(path, text)


# 1. Track actual online/offline state and expose it to the dashboard.
replace_once(
    'lib/core/offline/offline_sync_service.dart',
    "  String? _lastError;\n\n  bool get isSyncing => _syncing;\n  DateTime? get lastSyncAt => _lastSyncAt;\n  String? get lastError => _lastError;\n",
    "  String? _lastError;\n  bool _online = false;\n\n  bool get isSyncing => _syncing;\n  bool get isOnline => _online;\n  DateTime? get lastSyncAt => _lastSyncAt;\n  String? get lastError => _lastError;\n",
)
replace_once(
    'lib/core/offline/offline_sync_service.dart',
    "  Future<void> start() async {\n    if (_started) return;\n    _started = true;\n    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {\n      if (_hasNetwork(results)) unawaited(syncNow());\n    });\n    _timer = Timer.periodic(\n      const Duration(seconds: 30),\n      (_) => unawaited(syncNow()),\n    );\n    unawaited(syncNow());\n  }\n",
    "  Future<void> start() async {\n    if (_started) return;\n    _started = true;\n    final initial = await _connectivity.checkConnectivity();\n    _setOnline(_hasNetwork(initial));\n    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {\n      final connected = _hasNetwork(results);\n      if (!connected) {\n        _setOnline(false);\n        return;\n      }\n      unawaited(syncNow());\n    });\n    _timer = Timer.periodic(\n      const Duration(seconds: 30),\n      (_) => unawaited(syncNow()),\n    );\n    unawaited(syncNow());\n  }\n",
)
replace_once(
    'lib/core/offline/offline_sync_service.dart',
    "    final connectivity = await _connectivity.checkConnectivity();\n    if (!_hasNetwork(connectivity)) return;\n\n    final pending = _store.pendingEvents(user.id, limit: 50);\n",
    "    final connectivity = await _connectivity.checkConnectivity();\n    if (!_hasNetwork(connectivity)) {\n      _setOnline(false);\n      return;\n    }\n\n    final pending = _store.pendingEvents(user.id, limit: 50);\n",
)
replace_once(
    'lib/core/offline/offline_sync_service.dart',
    "    if (pending.isEmpty) {\n      try {\n        await _api.getOfflineBootstrap();\n        _lastError = null;\n        _lastSyncAt = DateTime.now();\n      } catch (_) {}\n      notifyListeners();\n      return;\n    }\n",
    "    if (pending.isEmpty) {\n      try {\n        await _api.getOfflineBootstrap();\n        _lastError = null;\n        _lastSyncAt = DateTime.now();\n        _setOnline(true);\n      } catch (error) {\n        _lastError = error.toString();\n        _setOnline(false);\n      }\n      notifyListeners();\n      return;\n    }\n",
)
replace_once(
    'lib/core/offline/offline_sync_service.dart',
    "      _lastSyncAt = DateTime.now();\n      try {\n        await _api.getOfflineBootstrap();\n      } catch (_) {}\n    } catch (error) {\n      _lastError = error.toString();\n    } finally {\n",
    "      _lastSyncAt = DateTime.now();\n      _setOnline(true);\n      try {\n        await _api.getOfflineBootstrap();\n      } catch (_) {}\n    } catch (error) {\n      _lastError = error.toString();\n      _setOnline(false);\n    } finally {\n",
)
replace_once(
    'lib/core/offline/offline_sync_service.dart',
    "  bool _hasNetwork(List<ConnectivityResult> results) =>\n      results.isNotEmpty &&\n      !results.every((item) => item == ConnectivityResult.none);\n",
    "  void _setOnline(bool value) {\n    if (_online == value) return;\n    _online = value;\n    notifyListeners();\n  }\n\n  bool _hasNetwork(List<ConnectivityResult> results) =>\n      results.isNotEmpty &&\n      !results.every((item) => item == ConnectivityResult.none);\n",
)

# 2. Persistent runtime NFC mode setting.
replace_once(
    'lib/core/offline/offline_store.dart',
    "  static const _bootstrapKey = 'patrol_bootstrap';\n",
    "  static const _bootstrapKey = 'patrol_bootstrap';\n  static const _nfcModeKey = 'nfc_operation_mode';\n",
)
replace_once(
    'lib/core/offline/offline_store.dart',
    "  OfflineBootstrap? cachedBootstrap() {\n    if (!_ready) return null;\n    final value = _cacheBox.get(_bootstrapKey);\n    if (value is! Map) return null;\n    try {\n      return OfflineBootstrap.fromJson(Map<String, dynamic>.from(value));\n    } catch (_) {\n      return null;\n    }\n  }\n\n  Future<void> purgeSyncedOlderThan(Duration age) async {\n",
    "  OfflineBootstrap? cachedBootstrap() {\n    if (!_ready) return null;\n    final value = _cacheBox.get(_bootstrapKey);\n    if (value is! Map) return null;\n    try {\n      return OfflineBootstrap.fromJson(Map<String, dynamic>.from(value));\n    } catch (_) {\n      return null;\n    }\n  }\n\n  String get nfcMode {\n    if (!_ready) return 'real';\n    final value = _cacheBox.get(_nfcModeKey);\n    return value == 'test' ? 'test' : 'real';\n  }\n\n  bool get isNfcTestMode => nfcMode == 'test';\n\n  Future<void> setNfcMode(String mode) async {\n    _ensureReady();\n    if (mode != 'test' && mode != 'real') {\n      throw ArgumentError.value(mode, 'mode', 'Mod NFC tidak sah.');\n    }\n    await _cacheBox.put(_nfcModeKey, mode);\n    notifyListeners();\n  }\n\n  Future<void> purgeSyncedOlderThan(Duration age) async {\n",
)

write(
    'lib/features/settings/nfc_settings_screen.dart',
    """import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/offline/offline_store.dart';

class NfcSettingsScreen extends StatefulWidget {
  const NfcSettingsScreen({required this.mockMode, super.key});

  final bool mockMode;

  @override
  State<NfcSettingsScreen> createState() => _NfcSettingsScreenState();
}

class _NfcSettingsScreenState extends State<NfcSettingsScreen> {
  final OfflineStore _store = OfflineStore.instance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _setMode(String mode) async {
    if (_saving || _store.nfcMode == mode) return;
    setState(() => _saving = true);
    try {
      await _store.setNfcMode(mode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == 'test'
                ? 'Mod Test NFC diaktifkan. Imbasan rondaan akan menggunakan dummy checkpoint.'
                : 'Mod Scan NFC Sebenar diaktifkan.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _store.nfcMode;
    final webSimulation = kIsWeb || widget.mockMode;
    return Scaffold(
      appBar: AppBar(title: const Text('Tetapan NFC')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF251A4F), Color(0xFF151827), Color(0xFF351315)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.nfc_rounded, size: 42),
                const SizedBox(height: 12),
                Text(
                  'Mod Operasi NFC',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  mode == 'test'
                      ? 'TEST • checkpoint dummy digunakan tanpa menyentuh tag NFC.'
                      : 'SEBENAR • telefon akan membaca tag NFC fizikal.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            selected: mode == 'test',
            icon: Icons.science_rounded,
            title: 'Mod Test NFC',
            description:
                'Untuk ujian aliran rondaan. Setiap tekan imbas akan memilih checkpoint aktif seterusnya sebagai dummy scan tanpa memerlukan tag fizikal.',
            badge: 'DUMMY SCAN',
            onTap: _saving ? null : () => _setMode('test'),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            selected: mode == 'real',
            icon: Icons.nfc_rounded,
            title: 'Mod Scan NFC Sebenar',
            description:
                'Untuk operasi sebenar. Aplikasi akan membuka pembaca NFC telefon dan hanya menerima tag checkpoint yang berdaftar.',
            badge: 'REAL NFC',
            onTap: _saving ? null : () => _setMode('real'),
          ),
          if (webSimulation) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Dalam preview web, NFC fizikal tidak tersedia. Mod Scan NFC Sebenar hanya berfungsi dalam APK/IPA pada peranti yang menyokong NFC.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.secondary : scheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: accent.withValues(alpha: 0.14),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(description),
                    const SizedBox(height: 10),
                    Chip(label: Text(badge)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
""",
)

# 3. Dashboard: disable network-dependent cards when line is down and add NFC setting.
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "import '../profile/profile_screen.dart';\n",
    "import '../profile/profile_screen.dart';\nimport '../settings/nfc_settings_screen.dart';\n",
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "  void _openPatrol() => _open(\n        PatrolScreen(\n          user: _user,\n          nfcService: widget.nfcService,\n          mockMode: widget.mockMode,\n          api: widget.api,\n        ),\n      );\n\n",
    "  void _openPatrol() => _open(\n        PatrolScreen(\n          user: _user,\n          nfcService: widget.nfcService,\n          mockMode: widget.mockMode,\n          api: widget.api,\n        ),\n      );\n\n  void _openNfcSettings() =>\n      _open(NfcSettingsScreen(mockMode: widget.mockMode));\n\n",
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "    final pending = _user.isManagement ? _store.pendingCount(_user.id) : 0;\n    final failed = _user.isManagement ? _store.failedCount(_user.id) : 0;\n\n    return Scaffold(\n",
    "    final pending = _user.isManagement ? _store.pendingCount(_user.id) : 0;\n    final failed = _user.isManagement ? _store.failedCount(_user.id) : 0;\n    final online = _sync.isOnline;\n    final nfcTestMode = _store.isNfcTestMode;\n\n    return Scaffold(\n",
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "            onPressed: _enableNotifications,\n",
    "            onPressed: online ? _enableNotifications : null,\n",
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "                        const _StatusPill(\n                          icon: Icons.offline_bolt_rounded,\n                          label: 'SEDIA LUAR TALIAN',\n                          color: Color(0xFF74B9FF),\n                        ),\n",
    "                        _StatusPill(\n                          icon: online\n                              ? Icons.cloud_done_rounded\n                              : Icons.cloud_off_rounded,\n                          label: online ? 'DALAM TALIAN' : 'LUAR TALIAN',\n                          color: online\n                              ? const Color(0xFF55E6C1)\n                              : const Color(0xFFFF7675),\n                        ),\n                        _StatusPill(\n                          icon: nfcTestMode\n                              ? Icons.science_rounded\n                              : Icons.nfc_rounded,\n                          label: nfcTestMode ? 'NFC • TEST' : 'NFC • SEBENAR',\n                          color: const Color(0xFFA29BFE),\n                        ),\n",
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "              const SizedBox(height: 22),\n              Text(\n                'Operasi',\n",
    "              if (!online) ...[\n                const SizedBox(height: 14),\n                Card(\n                  color: const Color(0xFF2B1719),\n                  child: const Padding(\n                    padding: EdgeInsets.all(14),\n                    child: Row(\n                      crossAxisAlignment: CrossAxisAlignment.start,\n                      children: [\n                        Icon(Icons.cloud_off_rounded, color: Color(0xFFFF7675)),\n                        SizedBox(width: 10),\n                        Expanded(\n                          child: Text(\n                            'Sambungan internet terputus. Fungsi dalam talian dikunci sementara. Mula Rondaan masih boleh digunakan kerana rekod disimpan pada peranti dan akan disegerakkan semula selepas talian pulih.',\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                ),\n              ],\n              const SizedBox(height: 22),\n              Text(\n                'Operasi',\n",
)
replace_once(
    'lib/features/dashboard/dashboard_screen.dart',
    "                    _MenuData(\n                      icon: Icons.directions_walk_rounded,\n                      title: 'Mula Rondaan',\n                      subtitle: 'Imbas checkpoint dan rekod lokasi',\n                      onTap: _openPatrol,\n                    ),\n",
    "                    _MenuData(\n                      icon: Icons.directions_walk_rounded,\n                      title: 'Mula Rondaan',\n                      subtitle: 'Imbas checkpoint dan rekod lokasi',\n                      onTap: _openPatrol,\n                    ),\n                    _MenuData(\n                      icon: nfcTestMode\n                          ? Icons.science_rounded\n                          : Icons.nfc_rounded,\n                      title: 'Tetapan NFC',\n                      subtitle: nfcTestMode\n                          ? 'Mod Test NFC aktif'\n                          : 'Mod Scan NFC Sebenar aktif',\n                      onTap: _openNfcSettings,\n                    ),\n",
)
for title in ['Kehadiran', 'Sejarah', 'Profil', 'Pentadbiran', 'Pemantauan']:
    path = 'lib/features/dashboard/dashboard_screen.dart'
    text = read(path)
    marker = f"title: '{title}',"
    index = text.find(marker)
    if index < 0:
        raise SystemExit(f'Dashboard menu not found: {title}')
    end = text.find('                    ),', index)
    if end < 0:
        raise SystemExit(f'Dashboard menu end not found: {title}')
    block = text[index:end]
    if 'enabled:' not in block:
        insert_at = block.rfind('\n') + 1
        block = block[:insert_at] + '                      enabled: online,\n' + block[insert_at:]
        text = text[:index] + block + text[end:]
        write(path, text)

text = read('lib/features/dashboard/dashboard_screen.dart')
marker = 'class _MenuData {'
if marker not in text:
    raise SystemExit('Dashboard menu classes marker not found')
text = text.split(marker, 1)[0] + """class _MenuData {
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
"""
write('lib/features/dashboard/dashboard_screen.dart', text)

# Admin discoverability for the NFC setting.
replace_once(
    'lib/features/admin/admin_screen.dart',
    "import 'user_maintenance_screen.dart';\n",
    "import 'user_maintenance_screen.dart';\nimport '../settings/nfc_settings_screen.dart';\n",
)
replace_once(
    'lib/features/admin/admin_screen.dart',
    "          _AdminMenuCard(\n            icon: Icons.picture_as_pdf_rounded,\n            title: 'Laporan',\n",
    "          _AdminMenuCard(\n            icon: Icons.nfc_rounded,\n            title: 'Tetapan NFC',\n            subtitle: 'Tukar antara Mod Test NFC dan Mod Scan NFC Sebenar.',\n            onTap: () => _open(\n              context,\n              NfcSettingsScreen(mockMode: mockMode),\n            ),\n          ),\n          const SizedBox(height: 10),\n          _AdminMenuCard(\n            icon: Icons.picture_as_pdf_rounded,\n            title: 'Laporan',\n",
)

# 4. Patrol scanning: runtime dummy mode versus real NFC mode.
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "      final raw = await showNfcScanPrompt(\n        context: context,\n        nfcService: widget.nfcService,\n        title: 'Imbas Checkpoint NFC',\n      );\n      if (raw == null) return;\n      final uid = _normalizeUid(raw.tagId);\n      final checkpoint = bootstrap.checkpoints\n          .where((item) => _normalizeUid(item.nfcUid) == uid)\n          .firstOrNull;\n      if (checkpoint == null) {\n        throw const ApiException(\n          'Tag ini bukan checkpoint aktif untuk Jabatan anda.',\n        );\n      }\n\n",
    "      late final String uid;\n      late final CachedCheckpoint checkpoint;\n      if (_store.isNfcTestMode) {\n        final dummy = _nextCheckpoint(bootstrap);\n        if (dummy == null) {\n          throw const ApiException(\n            'Semua checkpoint untuk sesi ini sudah direkod.',\n          );\n        }\n        await Future<void>.delayed(const Duration(milliseconds: 350));\n        checkpoint = dummy;\n        uid = _normalizeUid(dummy.nfcUid);\n      } else {\n        final raw = await showNfcScanPrompt(\n          context: context,\n          nfcService: widget.nfcService,\n          title: 'Imbas Checkpoint NFC',\n        );\n        if (raw == null) return;\n        uid = _normalizeUid(raw.tagId);\n        final matched = bootstrap.checkpoints\n            .where((item) => _normalizeUid(item.nfcUid) == uid)\n            .firstOrNull;\n        if (matched == null) {\n          throw const ApiException(\n            'Tag ini bukan checkpoint aktif untuk Jabatan anda.',\n          );\n        }\n        checkpoint = matched;\n      }\n\n",
)
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "          'dayKey': dayKey,\n        },\n",
    "          'dayKey': dayKey,\n          'nfcMode': _store.isNfcTestMode ? 'test' : 'real',\n        },\n",
)
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "            '${checkpoint.name} telah disimpan pada peranti dan akan disegerakkan secara automatik.',\n",
    "            _store.isNfcTestMode\n                ? 'DUMMY • ${checkpoint.name} telah direkod dan akan disegerakkan secara automatik.'\n                : '${checkpoint.name} telah disimpan pada peranti dan akan disegerakkan secara automatik.',\n",
)
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "    final bootstrap = _bootstrap ?? _store.cachedBootstrap();\n    final pending = _store.pendingCount(widget.user.id);\n",
    "    final bootstrap = _bootstrap ?? _store.cachedBootstrap();\n    final testNfc = _store.isNfcTestMode;\n    final pending = _store.pendingCount(widget.user.id);\n",
)
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "                icon: Icon(\n                  _scanning ? Icons.radar_rounded : Icons.nfc_rounded,\n                  size: 30,\n                ),\n                label: Text(\n                  _scanning ? 'MENGIMBAS…' : 'IMBAS CHECKPOINT',\n",
    "                icon: Icon(\n                  _scanning\n                      ? Icons.radar_rounded\n                      : testNfc\n                          ? Icons.science_rounded\n                          : Icons.nfc_rounded,\n                  size: 30,\n                ),\n                label: Text(\n                  _scanning\n                      ? (testNfc ? 'MENCUBA…' : 'MENGIMBAS…')\n                      : (testNfc\n                          ? 'DUMMY SCAN CHECKPOINT'\n                          : 'IMBAS CHECKPOINT'),\n",
)
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "              const SizedBox(height: 14),\n              _RouteCard(\n",
    "              if (testNfc) ...[\n                const SizedBox(height: 12),\n                const Card(\n                  child: Padding(\n                    padding: EdgeInsets.all(14),\n                    child: Row(\n                      children: [\n                        Icon(Icons.science_rounded, color: Color(0xFFA29BFE)),\n                        SizedBox(width: 10),\n                        Expanded(\n                          child: Text(\n                            'MOD TEST NFC AKTIF • Tekan butang dummy scan untuk merekod checkpoint seterusnya tanpa tag fizikal.',\n                            style: TextStyle(fontWeight: FontWeight.w800),\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                ),\n              ],\n              const SizedBox(height: 14),\n              _RouteCard(\n",
)

# 5. Checkpoint NFC writer button: full-width and always visible on narrow screens.
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "              Row(\n                crossAxisAlignment: CrossAxisAlignment.start,\n                children: [\n                  Expanded(\n                    child: TextField(\n                      controller: _uidController,\n                      textCapitalization: TextCapitalization.characters,\n                      decoration: const InputDecoration(\n                        labelText: 'ID tag NFC',\n                        hintText: 'Tekan Scan Tag untuk menetapkan tag',\n                        prefixIcon: Icon(Icons.nfc_rounded),\n                      ),\n                    ),\n                  ),\n                  const SizedBox(width: 8),\n                  SizedBox(\n                    height: 56,\n                    child: FilledButton.tonalIcon(\n                      onPressed: _scanning ? null : _scanTag,\n                      icon: const Icon(Icons.nfc_rounded),\n                      label: Text(_scanning ? 'Menulis…' : 'Scan Tag'),\n                    ),\n                  ),\n                ],\n              ),\n",
    "              TextField(\n                controller: _uidController,\n                textCapitalization: TextCapitalization.characters,\n                decoration: const InputDecoration(\n                  labelText: 'ID tag NFC',\n                  hintText: 'Tekan Scan Tag untuk menetapkan tag',\n                  prefixIcon: Icon(Icons.nfc_rounded),\n                ),\n              ),\n              const SizedBox(height: 10),\n              SizedBox(\n                width: double.infinity,\n                child: FilledButton.tonalIcon(\n                  onPressed: _scanning ? null : _scanTag,\n                  icon: const Icon(Icons.nfc_rounded),\n                  label: Text(_scanning ? 'MENULIS TAG…' : 'SCAN TAG'),\n                ),\n              ),\n              const SizedBox(height: 6),\n              const Align(\n                alignment: Alignment.centerLeft,\n                child: Text(\n                  'Untuk checkpoint baharu, tag akan ditulis dengan ID RimbaKawal. Untuk checkpoint sedia ada, Scan Tag akan menulis semula tag yang disentuh.',\n                  style: TextStyle(fontSize: 12),\n                ),\n              ),\n",
)

# 6. Command center missed-session/checkpoint intelligence.
replace_once(
    'worker/app.js',
    "  let completeCount = 0;\n  let alertCount = 0;\n\n  for (const user of usersResult.results ?? []) {\n",
    "  let completeCount = 0;\n  let alertCount = 0;\n  let missedSessionCount = 0;\n  let missedCheckpointCount = 0;\n  let scannedCheckpointCount = 0;\n  let dueCheckpointCount = 0;\n  let completedScannedCheckpointCount = 0;\n\n  for (const user of usersResult.results ?? []) {\n",
)
replace_once(
    'worker/app.js',
    "    let missedSessions = 0;\n    for (let index = 0; index < currentIndex; index += 1) {\n      const previousStartMs = scheduleDay.startMs + index * interval * 60000;\n      const previousEndMs = Math.min(\n        scheduleDay.endMs,\n        previousStartMs + interval * 60000,\n      );\n      const previousRows = userDayScans.filter((row) => {\n        const time = Date.parse(row.scanned_at);\n        return time >= previousStartMs && time < previousEndMs;\n      });\n      if (previousRows.length === 0) continue;\n      const unique = new Set(\n        previousRows\n          .map((row) => Number(row.checkpoint_id))\n          .filter((id) => id > 0),\n      );\n      if (expected > 0 && unique.size < expected) missedSessions += 1;\n    }\n\n",
    "    let missedSessions = 0;\n    let missedCheckpoints = 0;\n    let scannedCompletedCheckpoints = 0;\n    for (let index = 0; index < currentIndex; index += 1) {\n      const previousStartMs = scheduleDay.startMs + index * interval * 60000;\n      const previousEndMs = Math.min(\n        scheduleDay.endMs,\n        previousStartMs + interval * 60000,\n      );\n      const previousRows = userDayScans.filter((row) => {\n        const time = Date.parse(row.scanned_at);\n        return time >= previousStartMs && time < previousEndMs;\n      });\n      const unique = new Set(\n        previousRows\n          .map((row) => Number(row.checkpoint_id))\n          .filter((id) => id > 0),\n      );\n      scannedCompletedCheckpoints += unique.size;\n      if (expected > 0 && unique.size < expected) {\n        missedSessions += 1;\n        missedCheckpoints += expected - unique.size;\n      }\n    }\n    const scannedToday = scannedCompletedCheckpoints + uniqueCurrent.size;\n    const dueCheckpoints = expected * currentIndex;\n\n",
)
replace_once(
    'worker/app.js',
    "    if (status === 'complete') completeCount += 1;\n    if (status === 'late' || status === 'missed') alertCount += 1;\n\n    patrols.push({\n",
    "    if (status === 'complete') completeCount += 1;\n    if (status === 'late' || status === 'missed') alertCount += 1;\n    missedSessionCount += missedSessions;\n    missedCheckpointCount += missedCheckpoints;\n    scannedCheckpointCount += scannedToday;\n    dueCheckpointCount += dueCheckpoints;\n    completedScannedCheckpointCount += scannedCompletedCheckpoints;\n\n    patrols.push({\n",
)
replace_once(
    'worker/app.js',
    "      expectedCount: expected,\n      missedSessions,\n      lastScanAt: lastScan?.scanned_at ?? null,\n",
    "      expectedCount: expected,\n      missedSessions,\n      missedCheckpoints,\n      scannedToday,\n      dueCheckpoints,\n      completedScannedCheckpoints: scannedCompletedCheckpoints,\n      lastScanAt: lastScan?.scanned_at ?? null,\n",
)
replace_once(
    'worker/app.js',
    "      alerts: alertCount,\n      openIncidents: incidents.length,\n",
    "      alerts: alertCount,\n      missedSessions: missedSessionCount,\n      missedCheckpoints: missedCheckpointCount,\n      scannedCheckpoints: scannedCheckpointCount,\n      dueCheckpoints: dueCheckpointCount,\n      completedScannedCheckpoints: completedScannedCheckpointCount,\n      openIncidents: incidents.length,\n",
)
replace_once(
    'lib/features/admin/command_center_screen.dart',
    "                    _OperationsHero(\n                      summary: summary,\n                      generatedAt: data?.generatedAt,\n                      onMap: _openLiveMap,\n                    ),\n                    const SizedBox(height: 12),\n                    _AttendanceOverview(\n",
    "                    _OperationsHero(\n                      summary: summary,\n                      generatedAt: data?.generatedAt,\n                      onMap: _openLiveMap,\n                    ),\n                    const SizedBox(height: 12),\n                    _PatrolCoverageOverview(summary: summary),\n                    const SizedBox(height: 12),\n                    _AttendanceOverview(\n",
)
replace_once(
    'lib/features/admin/command_center_screen.dart',
    "class _HeroMetric extends StatelessWidget {\n",
    """class _PatrolCoverageOverview extends StatelessWidget {
  const _PatrolCoverageOverview({required this.summary});

  final Map<String, dynamic> summary;

  int _value(String key) => (summary[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final missedSessions = _value('missedSessions');
    final missedCheckpoints = _value('missedCheckpoints');
    final scanned = _value('scannedCheckpoints');
    final due = _value('dueCheckpoints');
    final completedScanned = _value('completedScannedCheckpoints');
    final coverage = due <= 0 ? 1.0 : (completedScanned / due).clamp(0.0, 1.0);
    final coveragePercent = (coverage * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_rounded),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Liputan Rondaan Hari Ini',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(label: Text('$coveragePercent% LIPUTAN')),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Sesi yang telah tamat sahaja dikira sebagai terlepas. Sesi semasa tidak dihukum sebelum waktunya tamat.',
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: coverage, minHeight: 9),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width,
                      child: _CoverageMetric(
                        icon: Icons.nfc_rounded,
                        value: scanned,
                        label: 'CHECKPOINT DIIMBAS',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CoverageMetric(
                        icon: Icons.location_off_rounded,
                        value: missedCheckpoints,
                        label: 'CHECKPOINT TERLEPAS',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CoverageMetric(
                        icon: Icons.event_busy_rounded,
                        value: missedSessions,
                        label: 'SESI TERLEPAS',
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

class _CoverageMetric extends StatelessWidget {
  const _CoverageMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.035),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _HeroMetric extends StatelessWidget {
""",
)
replace_once(
    'lib/features/admin/command_center_screen.dart',
    "    final missed = (row['missedSessions'] as num?)?.toInt() ?? 0;\n",
    "    final missed = (row['missedSessions'] as num?)?.toInt() ?? 0;\n    final missedCheckpoints =\n        (row['missedCheckpoints'] as num?)?.toInt() ?? 0;\n    final scannedToday = (row['scannedToday'] as num?)?.toInt() ?? 0;\n",
)
replace_once(
    'lib/features/admin/command_center_screen.dart',
    "                  Text(\n                    '$scanned/$expected checkpoint • imbasan terakhir $time${missed > 0 ? ' • $missed sesi terlepas' : ''}',\n                    style: Theme.of(context).textTheme.bodySmall,\n                  ),\n",
    "                  Text(\n                    '$scanned/$expected checkpoint sesi semasa • imbasan terakhir $time',\n                    style: Theme.of(context).textTheme.bodySmall,\n                  ),\n                  const SizedBox(height: 2),\n                  Text(\n                    'Hari ini: $scannedToday diimbas • $missedCheckpoints checkpoint terlepas • $missed sesi terlepas',\n                    style: Theme.of(context).textTheme.bodySmall?.copyWith(\n                          fontWeight: FontWeight.w700,\n                        ),\n                  ),\n",
)

# 7. Standardize all user-facing Batal actions: primary button first, full-width Batal below.
def stacked(primary: str, cancel_on_pressed: str) -> str:
    return f"""      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
{primary}
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: {cancel_on_pressed},
                child: const Text('Batal'),
              ),
            ],
          ),
        ),
      ],
"""

# Department form actions.
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "      actions: [\n        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Batal')),\n        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Menyimpan…' : 'Simpan')),\n      ],\n",
    stacked(
        "              FilledButton(\n                onPressed: _saving ? null : _save,\n                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),\n              ),\n",
        "_saving ? null : () => Navigator.of(context).pop(false)",
    ),
)
replace_once(
    'lib/features/admin/department_maintenance_screen.dart',
    "      actions: [\n        TextButton(\n          onPressed: _saving ? null : () => Navigator.of(context).pop(false),\n          child: const Text('Batal'),\n        ),\n        FilledButton(\n          onPressed: _saving || _scanning ? null : _save,\n          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),\n        ),\n      ],\n",
    stacked(
        "              FilledButton(\n                onPressed: _saving || _scanning ? null : _save,\n                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),\n              ),\n",
        "_saving ? null : () => Navigator.of(context).pop(false)",
    ),
)

# User edit/add forms.
replace_once(
    'lib/features/admin/user_maintenance_screen.dart',
    "      actions: [\n        TextButton(\n          onPressed: _saving ? null : () => Navigator.of(context).pop(false),\n          child: const Text('Batal'),\n        ),\n        FilledButton(\n          onPressed: _saving ? null : _save,\n          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),\n        ),\n      ],\n",
    stacked(
        "              FilledButton(\n                onPressed: _saving ? null : _save,\n                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),\n              ),\n",
        "_saving ? null : () => Navigator.of(context).pop(false)",
    ),
)
replace_once(
    'lib/features/admin/user_maintenance_screen.dart',
    "      actions: [\n        TextButton(\n          onPressed: _saving ? null : () => Navigator.of(context).pop(false),\n          child: const Text('Batal'),\n        ),\n        FilledButton(\n          onPressed: _saving ? null : _save,\n          child: Text(_saving ? 'Menyimpan…' : 'Tambah'),\n        ),\n      ],\n",
    stacked(
        "              FilledButton(\n                onPressed: _saving ? null : _save,\n                child: Text(_saving ? 'Menyimpan…' : 'Tambah'),\n              ),\n",
        "_saving ? null : () => Navigator.of(context).pop(false)",
    ),
)

# SOS management resolution form.
replace_once(
    'lib/features/admin/sos_management_screen.dart',
    "        actions: [\n          TextButton(\n            onPressed: () => Navigator.pop(context),\n            child: const Text('Batal'),\n          ),\n          FilledButton(\n            onPressed: () {\n              final value = controller.text.trim();\n              if (value.isEmpty) return;\n              Navigator.pop(context, value);\n            },\n            child: const Text('Selesai'),\n          ),\n        ],\n",
    """        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) return;
                    Navigator.pop(context, value);
                  },
                  child: const Text('Selesai'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
""",
)

# History delete confirmation.
replace_once(
    'lib/features/history/clocking_history_screen.dart',
    "        actions: [\n          TextButton(\n            onPressed: () => Navigator.of(context).pop(false),\n            child: const Text('Batal'),\n          ),\n          FilledButton(\n            onPressed: () => Navigator.of(context).pop(true),\n            style: FilledButton.styleFrom(\n              backgroundColor: Theme.of(context).colorScheme.error,\n              foregroundColor: Theme.of(context).colorScheme.onError,\n            ),\n            child: const Text('Padam Sesi'),\n          ),\n        ],\n",
    """        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: const Text('Padam Sesi'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
""",
)

# Web selfie form.
replace_once(
    'lib/features/attendance/web_selfie_capture_web.dart',
    "        actions: [\n          TextButton(\n            onPressed: () => Navigator.of(dialogContext).pop(false),\n            child: const Text('Batal'),\n          ),\n          FilledButton.icon(\n            onPressed: () => Navigator.of(dialogContext).pop(true),\n            icon: const Icon(Icons.camera_alt_rounded),\n            label: const Text('AMBIL GAMBAR'),\n          ),\n        ],\n",
    """        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('AMBIL GAMBAR'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
""",
)

# SOS alert resolution form.
replace_once(
    'lib/features/sos/sos_alert_gate.dart',
    "        actions: [\n          TextButton(\n            onPressed: () => Navigator.pop(context),\n            child: const Text('Batal'),\n          ),\n          FilledButton(\n            onPressed: () {\n              final note = controller.text.trim();\n              if (note.isEmpty) return;\n              Navigator.pop(context, note);\n            },\n            child: const Text('Sahkan Selesai'),\n          ),\n        ],\n",
    """        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () {
                    final note = controller.text.trim();
                    if (note.isEmpty) return;
                    Navigator.pop(context, note);
                  },
                  child: const Text('Sahkan Selesai'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
""",
)

# NFC scan prompt: retry primary first; Batal always a full-width button below.
replace_once(
    'lib/core/nfc/nfc_scan_prompt.dart',
    "        actions: [\n          TextButton(\n            onPressed: _closing ? null : _cancel,\n            child: const Text('Batal'),\n          ),\n          if (_error != null)\n            FilledButton.icon(\n              onPressed: _busy || _closing ? null : _startScan,\n              icon: const Icon(Icons.refresh_rounded),\n              label: const Text('Cuba Lagi'),\n            ),\n        ],\n",
    """        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  FilledButton.icon(
                    onPressed: _busy || _closing ? null : _startScan,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Cuba Lagi'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton(
                  onPressed: _closing ? null : _cancel,
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
""",
)

# Patrol incident form and SOS confirmation.
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "          actions: [\n            TextButton(\n              onPressed: () => Navigator.of(dialogContext).pop(false),\n              child: const Text('Batal'),\n            ),\n            FilledButton.icon(\n              onPressed: () => Navigator.of(dialogContext).pop(true),\n              icon: const Icon(Icons.save_rounded),\n              label: const Text('Simpan'),\n            ),\n          ],\n",
    """          actions: [
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Simpan'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Batal'),
                  ),
                ],
              ),
            ),
          ],
""",
)
replace_once(
    'lib/features/patrol/patrol_screen.dart',
    "        actions: [\n          TextButton(\n            onPressed: () => Navigator.of(context).pop(false),\n            child: const Text('Batal'),\n          ),\n          FilledButton.icon(\n            style: FilledButton.styleFrom(\n              backgroundColor: const Color(0xFFC0392B),\n              foregroundColor: Colors.white,\n            ),\n            onPressed: () => Navigator.of(context).pop(true),\n            icon: const Icon(Icons.sos_rounded),\n            label: const Text('AKTIFKAN SOS'),\n          ),\n        ],\n",
    """        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC0392B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.sos_rounded),
                  label: const Text('AKTIFKAN SOS'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        ],
""",
)

# 8. Bump release version for the new all-platform build.
replace_once('pubspec.yaml', 'version: 0.5.2+18\n', 'version: 0.5.3+19\n')

print('Operations/NFC/monitoring upgrade patch applied successfully.')
