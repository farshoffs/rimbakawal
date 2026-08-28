import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/nfc/nfc_service.dart';

class PatrolScreen extends StatefulWidget {
  const PatrolScreen({
    required this.nfcService,
    required this.mockMode,
    required this.api,
    super.key,
  });

  final NfcService nfcService;
  final bool mockMode;
  final ApiService api;

  @override
  State<PatrolScreen> createState() => _PatrolScreenState();
}

class _PatrolScreenState extends State<PatrolScreen> {
  final List<NfcLog> _scans = [];
  late Future<PatrolConfig> _configFuture;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _configFuture = widget.api.getPatrolConfig();
  }

  Future<void> _scanCheckpoint() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final available = await widget.nfcService.isAvailable();
      if (!available) {
        throw StateError(
          'NFC tidak tersedia. Pastikan telefon menyokong NFC dan NFC dihidupkan.',
        );
      }

      final raw = await widget.nfcService.scan();
      final saved = await widget.api.storeNfcScan(raw.tagId);
      if (!mounted) return;

      setState(() => _scans.insert(0, saved));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${saved.checkpointName ?? 'Checkpoint'} berjaya direkodkan.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('TimeoutException: ', '');
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan NFC'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(
                widget.mockMode ? Icons.science_outlined : Icons.nfc,
                size: 18,
              ),
              label: Text(widget.mockMode ? 'MOCK' : 'REAL NFC'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<PatrolConfig>(
                future: _configFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(snapshot.error.toString()),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }
                  final config = snapshot.data!;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            config.departmentName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sesi setiap ${config.sessionIntervalMinutes} minit • '
                            '${config.checkpointNames.length} checkpoint aktif',
                          ),
                          if (config.checkpointNames.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: config.checkpointNames
                                  .map((name) => Chip(label: Text(name)))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(_scanning ? Icons.radar : Icons.nfc, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        _scanning ? 'Menunggu tag NFC…' : 'Sedia untuk scan checkpoint',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Hanya NFC yang berdaftar dalam jabatan/sekolah anda akan diterima dan disimpan.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _scanning ? null : _scanCheckpoint,
                icon: const Icon(Icons.nfc),
                label: Text(_scanning ? 'Scanning…' : 'Scan NFC'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Scan sesi ini (${_scans.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _scans.isEmpty
                    ? const Center(child: Text('Belum ada scan dalam sesi ini.'))
                    : ListView.separated(
                        itemCount: _scans.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final scan = _scans[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.check)),
                            title: Text(scan.checkpointName ?? 'Checkpoint'),
                            subtitle: SelectableText(
                              '${scan.nfcUid}\n${_formatTime(scan.scannedAt)}',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
