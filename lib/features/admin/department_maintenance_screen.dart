import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';

class DepartmentMaintenanceScreen extends StatefulWidget {
  const DepartmentMaintenanceScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<DepartmentMaintenanceScreen> createState() =>
      _DepartmentMaintenanceScreenState();
}

class _DepartmentMaintenanceScreenState
    extends State<DepartmentMaintenanceScreen> {
  late Future<List<DepartmentRecord>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _future = widget.api.getAdminDepartments());
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

  Future<void> _openCheckpoints(DepartmentRecord department) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckpointMaintenanceScreen(
          api: widget.api,
          department: department,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jabatan / Sekolah & NFC')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editDepartment,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Tambah sekolah'),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Dalam RimbaKawal, Jabatan mewakili sekolah/lokasi operasi. '
                          'Setiap sekolah mempunyai kadar sesi rondaan dan senarai checkpoint NFC sendiri.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (departments.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada jabatan/sekolah.')),
                )
              else
                ...departments.map(
                  (department) => Card(
                    child: ListTile(
                      onTap: () => _openCheckpoints(department),
                      leading: CircleAvatar(
                        child: Icon(
                          department.active
                              ? Icons.school_rounded
                              : Icons.school_outlined,
                        ),
                      ),
                      title: Text(
                        department.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'Sesi: ${department.sessionIntervalMinutes} minit • '
                        '${department.checkpointCount} checkpoint aktif'
                        '${department.active ? '' : ' • TIDAK AKTIF'}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Tetapan sekolah',
                        onPressed: () => _editDepartment(department),
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ),
                  ),
                ),
            ],
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
    _active = widget.department?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final interval = int.tryParse(_intervalController.text.trim());
    if (name.length < 2 || interval == null) {
      setState(() => _error = 'Masukkan nama sekolah dan kadar sesi yang sah.');
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
        );
      } else {
        await widget.api.updateDepartment(
          DepartmentRecord(
            id: existing.id,
            name: name,
            sessionIntervalMinutes: interval,
            active: _active,
            checkpointCount: existing.checkpointCount,
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
      title: Text(widget.department == null ? 'Tambah sekolah' : 'Tetapan sekolah'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Jabatan / Sekolah',
                  prefixIcon: Icon(Icons.school_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempoh satu sesi (minit)',
                  helperText: 'Default: 120 minit (2 jam)',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),
              if (widget.department != null) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Jabatan / sekolah aktif'),
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

class CheckpointMaintenanceScreen extends StatefulWidget {
  const CheckpointMaintenanceScreen({
    required this.api,
    required this.department,
    super.key,
  });

  final ApiService api;
  final DepartmentRecord department;

  @override
  State<CheckpointMaintenanceScreen> createState() =>
      _CheckpointMaintenanceScreenState();
}

class _CheckpointMaintenanceScreenState
    extends State<CheckpointMaintenanceScreen> {
  late Future<List<CheckpointRecord>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = widget.api.getAdminCheckpoints(widget.department.id);
    });
  }

  Future<void> _editCheckpoint([CheckpointRecord? checkpoint]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _CheckpointDialog(
        api: widget.api,
        departmentId: widget.department.id,
        checkpoint: checkpoint,
      ),
    );
    if (changed == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.department.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editCheckpoint,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah checkpoint'),
      ),
      body: FutureBuilder<List<CheckpointRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final checkpoints = snapshot.data ?? const <CheckpointRecord>[];
          if (checkpoints.isEmpty) {
            return const Center(child: Text('Belum ada checkpoint NFC.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: checkpoints.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final checkpoint = checkpoints[index];
              return Card(
                child: ListTile(
                  onTap: () => _editCheckpoint(checkpoint),
                  leading: CircleAvatar(child: Text('${checkpoint.position}')),
                  title: Text(
                    checkpoint.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: SelectableText(
                    '${checkpoint.nfcUid}${checkpoint.active ? '' : ' • TIDAK AKTIF'}',
                  ),
                  trailing: const Icon(Icons.edit_rounded),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CheckpointDialog extends StatefulWidget {
  const _CheckpointDialog({
    required this.api,
    required this.departmentId,
    this.checkpoint,
  });

  final ApiService api;
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

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final uid = _uidController.text.trim().toUpperCase();
    final position = int.tryParse(_positionController.text.trim());
    if (name.isEmpty || uid.isEmpty || position == null) {
      setState(() => _error = 'Lengkapkan nama, UID NFC dan susunan checkpoint.');
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
      title: Text(widget.checkpoint == null ? 'Tambah checkpoint' : 'Edit checkpoint'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama checkpoint',
                  hintText: 'Contoh: Checkpoint 1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _uidController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'NFC UID',
                  hintText: 'Contoh: 04:A1:B2:C3:D4:E5:F6',
                  prefixIcon: Icon(Icons.nfc_rounded),
                ),
              ),
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
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    );
  }
}
