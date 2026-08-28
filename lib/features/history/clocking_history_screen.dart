import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class ClockingHistoryScreen extends StatefulWidget {
  const ClockingHistoryScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<ClockingHistoryScreen> createState() => _ClockingHistoryScreenState();
}

class _ClockingHistoryScreenState extends State<ClockingHistoryScreen> {
  late Future<List<NfcLog>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getScans();
  }

  void _refresh() {
    setState(() => _future = widget.api.getScans());
  }

  String _format(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clocking History'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<List<NfcLog>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
              ),
            );
          }
          final scans = snapshot.data ?? const <NfcLog>[];
          if (scans.isEmpty) {
            return const Center(child: Text('Belum ada rekod NFC.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: scans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final scan = scans[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.nfc_rounded)),
                  title: SelectableText(scan.nfcUid),
                  subtitle: Text(_format(scan.scannedAt)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
