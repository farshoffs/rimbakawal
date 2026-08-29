import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class ClockingHistoryScreen extends StatefulWidget {
  const ClockingHistoryScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<ClockingHistoryScreen> createState() => _ClockingHistoryScreenState();
}

class _ClockingHistoryScreenState extends State<ClockingHistoryScreen> {
  DateTime _selectedDate = DateTime.now();
  late Future<HistoryDay> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getHistory(_selectedDate);
  }

  void _load(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    setState(() {
      _selectedDate = normalized;
      _future = widget.api.getHistory(normalized);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Pilih tarikh rekod',
    );
    if (picked != null) _load(picked);
  }

  String _formatDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sejarah Rondaan'),
        actions: [
          IconButton(
            tooltip: 'Muat semula',
            onPressed: () => _load(_selectedDate),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tarikh: ${_formatDate(_selectedDate)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Hari ini'),
                            selected: _sameDay(_selectedDate, today),
                            onSelected: (_) => _load(today),
                          ),
                          ChoiceChip(
                            label: const Text('Semalam'),
                            selected: _sameDay(_selectedDate, yesterday),
                            onSelected: (_) => _load(yesterday),
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.calendar_month_rounded,
                              size: 18,
                            ),
                            label: const Text('Pilih tarikh'),
                            onPressed: _pickDate,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<HistoryDay>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final history = snapshot.data!;
                  if (history.sessions.isEmpty) {
                    return const Center(
                      child: Text('Tiada sesi rondaan untuk tarikh ini.'),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: history.sessions.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${history.department} • Sesi rondaan setiap ${history.sessionIntervalMinutes} minit • rekod mengikut sesi Jabatan',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        );
                      }
                      return _SessionCard(
                        session: history.sessions[index - 1],
                        formatTime: _formatTime,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.formatTime});

  final HistorySession session;
  final String Function(DateTime) formatTime;

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) {
        return MemoryImage(base64Decode(picture.substring(comma + 1)));
      }
    }
    return NetworkImage(picture);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = session.isMissed
        ? scheme.error
        : session.isComplete
        ? Colors.greenAccent
        : scheme.secondary;
    final statusLabel = switch (session.status) {
      'complete' => 'LENGKAP',
      'missed' => 'CHECKPOINT TERLEPAS',
      'in_progress' => 'SESI SEMASA',
      'no_checkpoints' => 'TIADA CHECKPOINT',
      _ => session.status.toUpperCase(),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: session.isMissed
              ? scheme.error.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.08),
          width: session.isMissed ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: _imageProvider(session.profilePicture),
                  child: _imageProvider(session.profilePicture) == null
                      ? Text(
                          session.userName.isEmpty ? '?' : session.userName[0],
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.userName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sesi Rondaan ${session.index + 1} • ${formatTime(session.startAt)} - ${formatTime(session.endAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${session.scannedCount}/${session.expectedCount} checkpoint direkodkan',
            ),
            if (session.missingCheckpointNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (session.isMissed ? scheme.error : scheme.secondary)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${session.isMissed ? 'TERLEPAS' : 'Belum diimbas'}: ${session.missingCheckpointNames.join(', ')}',
                  style: TextStyle(
                    color: session.isMissed ? scheme.error : null,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            if (session.scans.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...session.scans.map(
                (scan) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nfc_rounded),
                  title: Text(scan.checkpointName ?? 'Checkpoint tidak dikenal pasti'),
                  subtitle: Text(
                    '${scan.userName ?? session.userName} • ${scan.nfcUid} • ${formatTime(scan.scannedAt)}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
