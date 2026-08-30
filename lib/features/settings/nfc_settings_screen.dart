import 'package:flutter/foundation.dart';
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
                colors: [
                  Color(0xFF251A4F),
                  Color(0xFF151827),
                  Color(0xFF351315),
                ],
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
