import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
                    '${department.checkpointCount} checkpoint aktif'
                    '${department.attendanceLatitude == null ? ' • KAWASAN BELUM DITETAPKAN' : ' • Radius kehadiran ${department.attendanceRadiusMeters}m'}'
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
  late final TextEditingController _radiusController;
  late TimeOfDay _startTime;
  LatLng? _attendancePoint;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.department?.name ?? '');
    _intervalController = TextEditingController(
      text: (widget.department?.sessionIntervalMinutes ?? 120).toString(),
    );
    _radiusController = TextEditingController(
      text: (widget.department?.attendanceRadiusMeters ?? 200).toString(),
    );
    final latitude = widget.department?.attendanceLatitude;
    final longitude = widget.department?.attendanceLongitude;
    if (latitude != null && longitude != null) {
      _attendancePoint = LatLng(latitude, longitude);
    }
    final startMinutes = widget.department?.sessionStartMinutes ?? 420;
    _startTime = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    _active = widget.department?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _error = 'Kebenaran lokasi diperlukan untuk memilih kawasan sekolah.');
      return;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    if (mounted) {
      setState(() => _attendancePoint = LatLng(position.latitude, position.longitude));
    }
  }

  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'Jam mula sesi rondaan',
    );
    if (selected != null && mounted) setState(() => _startTime = selected);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final interval = int.tryParse(_intervalController.text.trim());
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final radius = int.tryParse(_radiusController.text.trim());
    if (name.length < 2 || interval == null || radius == null ||
        radius < 30 || radius > 2000 || _attendancePoint == null) {
      setState(() => _error = 'Masukkan nama Jabatan dan kadar sesi yang sah.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.department;
      if (existing == null) {
        await widget.api.createDepartment(
          name: name,
          sessionIntervalMinutes: interval,
          sessionStartMinutes: startMinutes,
          attendanceLatitude: _attendancePoint!.latitude,
          attendanceLongitude: _attendancePoint!.longitude,
          attendanceRadiusMeters: radius,
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
            attendanceLatitude: _attendancePoint!.latitude,
            attendanceLongitude: _attendancePoint!.longitude,
            attendanceRadiusMeters: radius,
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
      title: Text(widget.department == null ? 'Tambah Jabatan' : 'Tetapan Jabatan'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Jabatan',
                  prefixIcon: Icon(Icons.account_tree_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempoh satu sesi (minit)',
                  helperText: 'Nilai asal: 120 minit (2 jam)',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Jam mula rondaan'),
                subtitle: Text('Sesi 1 bermula pada ${_startTime.format(context)}'),
                trailing: FilledButton.tonal(
                  onPressed: _pickStartTime,
                  child: Text(_startTime.format(context)),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kawasan sekolah untuk kehadiran',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _attendancePoint ?? const LatLng(4.2105, 101.9758),
                      initialZoom: _attendancePoint == null ? 5.5 : 17,
                      onTap: (_, point) => setState(() => _attendancePoint = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'my.rimbakawal.app',
                      ),
                      if (_attendancePoint != null) ...[
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: _attendancePoint!,
                              radius: (int.tryParse(_radiusController.text) ?? 200).toDouble(),
                              useRadiusInMeter: true,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
                              borderColor: Theme.of(context).colorScheme.primary,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _attendancePoint!,
                              width: 44,
                              height: 44,
                              child: const Icon(Icons.school_rounded, size: 36),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Guna lokasi semasa'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Radius kehadiran (meter)',
                  helperText: 'Minimum 30m, maksimum 2000m',
                  prefixIcon: Icon(Icons.radar_rounded),
                ),
              ),
              if (widget.department != null) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jabatan aktif'),
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
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
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
