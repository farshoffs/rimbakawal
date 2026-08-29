import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_service.dart';
import '../../core/nfc/nfc_service.dart';

class DepartmentMaintenanceScreen extends StatefulWidget {
  const DepartmentMaintenanceScreen({
    required this.api,
    required this.nfcService,
    required this.mockMode,
    super.key,
  });

  final ApiService api;
  final NfcService nfcService;
  final bool mockMode;

  @override
  State<DepartmentMaintenanceScreen> createState() =>
      _DepartmentMaintenanceScreenState();
}

class _DepartmentMaintenanceScreenState
    extends State<DepartmentMaintenanceScreen> {
  late Future<List<DepartmentRecord>> _future;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _refreshKey++;
      _future = widget.api.getAdminDepartments();
    });
  }

  Future<void> _editDepartment([DepartmentRecord? department]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _DepartmentDialog(
        api: widget.api,
        department: department,
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  Future<void> _editCheckpoint(
    DepartmentRecord department, [
    CheckpointRecord? checkpoint,
  ]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _CheckpointDialog(
        api: widget.api,
        nfcService: widget.nfcService,
        mockMode: widget.mockMode,
        departmentId: department.id,
        checkpoint: checkpoint,
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jabatan dan Checkpoint')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editDepartment,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Tambah Jabatan'),
      ),
      body: FutureBuilder<List<DepartmentRecord>>(
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
          final departments = snapshot.data ?? const <DepartmentRecord>[];
          if (departments.isEmpty) {
            return const Center(child: Text('Belum ada Jabatan.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: departments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final department = departments[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  key: ValueKey('${department.id}-$_refreshKey'),
                  leading: CircleAvatar(
                    child: Icon(
                      department.active
                          ? Icons.account_tree_rounded
                          : Icons.account_tree_outlined,
                    ),
                  ),
                  title: Text(
                    department.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'Mula ${TimeOfDay(hour: department.sessionStartMinutes ~/ 60, minute: department.sessionStartMinutes % 60).format(context)} • '
                    'Sesi setiap ${department.sessionIntervalMinutes} minit • '
                    '${department.checkpointCount} checkpoint aktif • '
                    '${department.attendanceLatitude == null ? 'Kawasan kehadiran belum ditetapkan' : 'Kehadiran ${department.attendanceRadiusMeters}m'}'
                    '${department.active ? '' : ' • TIDAK AKTIF'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Tetapan Jabatan',
                    onPressed: () => _editDepartment(department),
                    icon: const Icon(Icons.settings_rounded),
                  ),
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FutureBuilder<List<CheckpointRecord>>(
                            future: widget.api.getAdminCheckpoints(department.id),
                            builder: (context, checkpointSnapshot) {
                              if (checkpointSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (checkpointSnapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    checkpointSnapshot.error.toString(),
                                  ),
                                );
                              }
                              final checkpoints = checkpointSnapshot.data ??
                                  const <CheckpointRecord>[];
                              if (checkpoints.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Belum ada checkpoint.'),
                                );
                              }
                              return Column(
                                children: checkpoints
                                    .map(
                                      (checkpoint) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        onTap: () => _editCheckpoint(
                                          department,
                                          checkpoint,
                                        ),
                                        leading: CircleAvatar(
                                          child: Text('${checkpoint.position}'),
                                        ),
                                        title: Text(
                                          checkpoint.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: SelectableText(
                                          '${checkpoint.nfcUid}'
                                          '${checkpoint.active ? '' : ' • TIDAK AKTIF'}',
                                        ),
                                        trailing: const Icon(Icons.edit_rounded),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _editCheckpoint(department),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Tambah Checkpoint'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DepartmentDialog extends StatefulWidget {
  const _DepartmentDialog({required this.api, this.department});

  final ApiService api;
  final DepartmentRecord? department;

  @override
  State<_DepartmentDialog> createState() => _DepartmentDialogState();
}

class _DepartmentDialogState extends State<_DepartmentDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _intervalController;
  late final TextEditingController _locationLabelController;
  late TimeOfDay _startTime;
  late bool _active;
  double? _latitude;
  double? _longitude;
  double _radius = 150;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.department?.name ?? '');
    _intervalController = TextEditingController(text: (widget.department?.sessionIntervalMinutes ?? 120).toString());
    _locationLabelController = TextEditingController(text: widget.department?.attendanceLocationLabel ?? '');
    final startMinutes = widget.department?.sessionStartMinutes ?? 420;
    _startTime = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    _active = widget.department?.active ?? true;
    _latitude = widget.department?.attendanceLatitude;
    _longitude = widget.department?.attendanceLongitude;
    _radius = (widget.department?.attendanceRadiusMeters ?? 150).toDouble();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalController.dispose();
    _locationLabelController.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(context: context, initialTime: _startTime, helpText: 'Jam mula sesi rondaan');
    if (selected != null && mounted) setState(() => _startTime = selected);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final interval = int.tryParse(_intervalController.text.trim());
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    if (name.length < 2 || interval == null) {
      setState(() => _error = 'Masukkan nama Jabatan dan kadar sesi yang sah.');
      return;
    }
    if (_latitude == null || _longitude == null) {
      setState(() => _error = 'Tandakan pusat kawasan sekolah pada peta untuk fungsi kehadiran.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final existing = widget.department;
      if (existing == null) {
        await widget.api.createDepartment(
          name: name,
          sessionIntervalMinutes: interval,
          sessionStartMinutes: startMinutes,
          attendanceLatitude: _latitude!,
          attendanceLongitude: _longitude!,
          attendanceRadiusMeters: _radius.round(),
          attendanceLocationLabel: _locationLabelController.text.trim(),
        );
      } else {
        await widget.api.updateDepartment(
          DepartmentRecord(
            id: existing.id,
            name: name,
            sessionIntervalMinutes: interval,
            sessionStartMinutes: startMinutes,
            active: _active,
            checkpointCount: existing.checkpointCount,
            attendanceLatitude: _latitude,
            attendanceLongitude: _longitude,
            attendanceRadiusMeters: _radius.round(),
            attendanceLocationLabel: _locationLabelController.text.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(_latitude ?? 5.69582, _longitude ?? 100.53720);
    return AlertDialog(
      title: Text(widget.department == null ? 'Tambah Jabatan' : 'Tetapan Jabatan'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama Jabatan', prefixIcon: Icon(Icons.account_tree_rounded)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tempoh satu sesi (minit)', helperText: 'Nilai asal: 120 minit (2 jam)', prefixIcon: Icon(Icons.timer_outlined)),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final timeButton = FilledButton.tonalIcon(
                    onPressed: _pickStartTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(_startTime.format(context)),
                  );
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jam mula rondaan',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text('Sesi 1 bermula pada ${_startTime.format(context)}'),
                    ],
                  );
                  if (constraints.maxWidth < 430) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        const SizedBox(height: 10),
                        timeButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Icon(Icons.schedule_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: details),
                      const SizedBox(width: 12),
                      timeButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text('Kawasan Kehadiran', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Tekan pada peta untuk menetapkan pusat sekolah. Bulatan menunjukkan radius yang dibenarkan untuk punch masuk/keluar.'),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 290,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: _latitude == null ? 15 : 17,
                      onTap: (_, point) => setState(() { _latitude = point.latitude; _longitude = point.longitude; }),
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'dev.rimbakawal.rimbakawal'),
                      if (_latitude != null && _longitude != null)
                        CircleLayer(circles: [CircleMarker(point: LatLng(_latitude!, _longitude!), radius: _radius, useRadiusInMeter: true, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), borderColor: Theme.of(context).colorScheme.primary, borderStrokeWidth: 2)]),
                      if (_latitude != null && _longitude != null)
                        MarkerLayer(markers: [Marker(point: LatLng(_latitude!, _longitude!), width: 48, height: 48, child: const Icon(Icons.school_rounded, size: 38))]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.radar_rounded),
                const SizedBox(width: 8),
                Expanded(child: Slider(value: _radius.clamp(30.0, 1000.0).toDouble(), min: 30, max: 1000, divisions: 97, label: '${_radius.round()}m', onChanged: (value) => setState(() => _radius = value))),
                SizedBox(width: 72, child: Text('${_radius.round()} m', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900))),
              ]),
              TextField(
                controller: _locationLabelController,
                decoration: const InputDecoration(labelText: 'Label lokasi (pilihan)', hintText: 'Contoh: SMK Bandar Baru Sungai Lalang', prefixIcon: Icon(Icons.location_city_rounded)),
              ),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 8),
                SelectableText('Pusat: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}'),
              ],
              if (widget.department != null) ...[
                const SizedBox(height: 8),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Jabatan aktif'), value: _active, onChanged: (value) => setState(() => _active = value)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Menyimpan…' : 'Simpan')),
      ],
    );
  }
}

class _CheckpointDialog extends StatefulWidget {
  const _CheckpointDialog({
    required this.api,
    required this.nfcService,
    required this.mockMode,
    required this.departmentId,
    this.checkpoint,
  });

  final ApiService api;
  final NfcService nfcService;
  final bool mockMode;
  final int departmentId;
  final CheckpointRecord? checkpoint;

  @override
  State<_CheckpointDialog> createState() => _CheckpointDialogState();
}

class _CheckpointDialogState extends State<_CheckpointDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _uidController;
  late final TextEditingController _positionController;
  late bool _active;
  bool _saving = false;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.checkpoint?.name ?? '');
    _uidController = TextEditingController(text: widget.checkpoint?.nfcUid ?? '');
    _positionController = TextEditingController(
      text: (widget.checkpoint?.position ?? 1).toString(),
    );
    _active = widget.checkpoint?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _uidController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  Future<void> _scanUid() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final available = await widget.nfcService.isAvailable();
      if (!available) throw StateError('NFC tidak tersedia pada peranti ini.');
      final result = await widget.nfcService.scan();
      if (!mounted) return;
      _uidController.text = result.tagId.toUpperCase();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final uid = _uidController.text.trim().toUpperCase();
    final position = int.tryParse(_positionController.text.trim());
    if (name.isEmpty || uid.isEmpty || position == null) {
      setState(() => _error = 'Lengkapkan nama, UID tag NFC dan susunan checkpoint.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.checkpoint;
      if (existing == null) {
        await widget.api.createCheckpoint(
          departmentId: widget.departmentId,
          name: name,
          nfcUid: uid,
          position: position,
        );
      } else {
        await widget.api.updateCheckpoint(
          CheckpointRecord(
            id: existing.id,
            departmentId: widget.departmentId,
            name: name,
            nfcUid: uid,
            position: position,
            active: _active,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.checkpoint == null ? 'Tambah Checkpoint' : 'Edit Checkpoint'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama checkpoint',
                  hintText: 'Contoh: Pintu Utama',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _uidController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'UID tag NFC',
                        hintText: 'Imbas tag atau masukkan UID',
                        prefixIcon: Icon(Icons.nfc_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton.tonalIcon(
                      onPressed: _scanning ? null : _scanUid,
                      icon: const Icon(Icons.nfc_rounded),
                      label: Text(_scanning ? 'Mengimbas…' : 'Imbas'),
                    ),
                  ),
                ],
              ),
              if (widget.mockMode) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Versi web menggunakan simulasi NFC untuk ujian konfigurasi.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _positionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Susunan checkpoint',
                  prefixIcon: Icon(Icons.format_list_numbered_rounded),
                ),
              ),
              if (widget.checkpoint != null) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Checkpoint aktif'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving || _scanning ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    );
  }
}
