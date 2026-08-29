import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/app_user.dart';

import '../sos/sos_alert_api.dart';

class SosManagementScreen extends StatefulWidget {
  const SosManagementScreen({super.key});

  @override
  State<SosManagementScreen> createState() => _SosManagementScreenState();
}

class _SosManagementScreenState extends State<SosManagementScreen> {
  final SosAlertApi _api = SosAlertApi.instance;
  Timer? _timer;
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final events = await _api.fetchManagedEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> event) async {
    final id = (event['id'] as num?)?.toInt();
    if (id == null) return;
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tandakan SOS Selesai'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SOS oleh ${event['nama'] ?? '-'} akan ditandakan selesai. Masukkan catatan penyelesaian.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Catatan penyelesaian',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;

    try {
      await _api.resolve(id, note);
      await _refresh(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS telah ditandakan selesai.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  String _dateTime(Object? value) {
    final date = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (date == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final active = _events.where((row) => row['status'] == 'active').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengurusan SOS'),
        actions: [
          IconButton(
            tooltip: 'Muat semula',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _events.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4A0B13), Color(0xFF21101C)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sos_rounded,
                          size: 48,
                          color: Color(0xFFFF7675),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$active SOS AKTIF',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const Text(
                                'Paparan dikemas kini secara automatik setiap 8 saat. Penyelesaian SOS memerlukan catatan audit.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_events.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Tiada rekod SOS.')),
                      ),
                    )
                  else
                    ..._events.map((event) {
                      final isActive = event['status'] == 'active';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          color: isActive
                              ? const Color(0xFF2C1116)
                              : const Color(0xFF10251F),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.sos_rounded
                                          : Icons.task_alt_rounded,
                                      color: isActive
                                          ? const Color(0xFFFF7675)
                                          : const Color(0xFF55EFC4),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        event['nama'] as String? ?? '-',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Chip(
                                      label: Text(isActive ? 'AKTIF' : 'SELESAI'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${labelJawatan(event['jawatan'] as String?)} • ${event['jabatan'] ?? '-'}',
                                ),
                                Text('Dicetus: ${_dateTime(event['triggered_at'])}'),
                                const SizedBox(height: 8),
                                Text(event['note'] as String? ?? 'Tiada catatan SOS.'),
                                if (!isActive) ...[
                                  const Divider(height: 24),
                                  Text(
                                    'Diselesaikan: ${_dateTime(event['resolved_at'])}',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  Text('Oleh: ${event['resolved_by_name'] ?? '-'}'),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Catatan: ${event['resolution_note'] ?? '-'}',
                                  ),
                                ],
                                if (isActive) ...[
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    onPressed: () => _resolve(event),
                                    icon: const Icon(Icons.task_alt_rounded),
                                    label: const Text('TANDAKAN SELESAI'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
