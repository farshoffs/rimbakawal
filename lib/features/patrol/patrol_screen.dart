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
    _refreshConfig();
  }

  void _refreshConfig() {
    setState(() => _configFuture = widget.api.getPatrolConfig());
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
      _refreshConfig();
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

  Future<void> _reportIncident(NfcLog scan) async {
    final noteController = TextEditingController();
    String category = 'Keselamatan';
    String severity = 'normal';

    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Lapor Insiden • ${scan.checkpointName ?? 'Checkpoint'}'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: const [
                      DropdownMenuItem(value: 'Keselamatan', child: Text('Keselamatan')),
                      DropdownMenuItem(value: 'Kerosakan', child: Text('Kerosakan')),
                      DropdownMenuItem(value: 'Kebersihan', child: Text('Kebersihan')),
                      DropdownMenuItem(value: 'Akses', child: Text('Akses')),
                      DropdownMenuItem(value: 'Lain-lain', child: Text('Lain-lain')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => category = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: severity,
                    decoration: const InputDecoration(labelText: 'Keutamaan'),
                    items: const [
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem(value: 'important', child: Text('Penting')),
                      DropdownMenuItem(value: 'urgent', child: Text('Segera')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => severity = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Catatan',
                      hintText: 'Contoh: Lampu koridor rosak / pintu tidak berkunci.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Hantar'),
            ),
          ],
        ),
      ),
    );

    if (submit != true) {
      noteController.dispose();
      return;
    }

    final note = noteController.text.trim();
    noteController.dispose();
    if (note.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan catatan insiden.')),
      );
      return;
    }

    try {
      await widget.api.createIncident(
        checkpointId: scan.checkpointId,
        category: category,
        severity: severity,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insiden dihantar ke Command Center Admin.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
        title: const Text('Patrol'),
        actions: [
          IconButton(
            tooltip: 'Refresh route',
            onPressed: _refreshConfig,
            icon: const Icon(Icons.refresh_rounded),
          ),
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
                  final total = config.checkpoints.length;
                  final completed = config.completedCount;
                  final progress = total == 0 ? 0.0 : completed / total;
                  final next = config.nextCheckpoint;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  config.departmentName,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                              if (config.routeOrderEnforced)
                                const Chip(
                                  avatar: Icon(Icons.route_rounded, size: 16),
                                  label: Text('ORDERED'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sesi ${config.sessionIndex + 1} • setiap ${config.sessionIntervalMinutes} minit',
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 6),
                          Text('$completed / $total checkpoint selesai'),
                          const SizedBox(height: 12),
                          if (next != null)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Theme.of(context).colorScheme.secondaryContainer,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(child: Text('${next.position}')),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'CHECKPOINT SETERUSNYA',
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                        ),
                                        Text(
                                          next.name,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                                        ),
                                        if (next.instruction != null && next.instruction!.isNotEmpty)
                                          Text(next.instruction!),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (total > 0)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.verified_rounded, color: Colors.green),
                              title: Text('Semua checkpoint sesi ini selesai.'),
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: config.checkpoints
                                .map(
                                  (checkpoint) => Chip(
                                    avatar: Icon(
                                      checkpoint.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                                      size: 17,
                                    ),
                                    label: Text('${checkpoint.position}. ${checkpoint.name}'),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _scanning ? null : _scanCheckpoint,
                icon: Icon(_scanning ? Icons.radar : Icons.nfc),
                label: Text(_scanning ? 'Menunggu NFC…' : 'Scan Checkpoint'),
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
                'Scan baru (${_scans.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _scans.isEmpty
                    ? const Center(
                        child: Text(
                          'Scan checkpoint mengikut turutan yang dipaparkan.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _scans.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final scan = _scans[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.check_rounded)),
                              title: Text(scan.checkpointName ?? 'Checkpoint'),
                              subtitle: Text(_formatTime(scan.scannedAt)),
                              trailing: IconButton(
                                tooltip: 'Lapor insiden',
                                onPressed: () => _reportIncident(scan),
                                icon: const Icon(Icons.report_problem_outlined),
                              ),
                            ),
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
