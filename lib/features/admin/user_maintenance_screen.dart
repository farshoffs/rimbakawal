import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';

class UserMaintenanceScreen extends StatefulWidget {
  const UserMaintenanceScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<UserMaintenanceScreen> createState() => _UserMaintenanceScreenState();
}

class _UserMaintenanceScreenState extends State<UserMaintenanceScreen> {
  late Future<_UserAdminData> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<_UserAdminData> _load() async {
    final users = await widget.api.getAdminUsers();
    final departments = await widget.api.getAdminDepartments();
    return _UserAdminData(users: users, departments: departments);
  }

  Future<void> _addUser(List<DepartmentRecord> departments) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AddUserDialog(api: widget.api, departments: departments),
    );
    if (changed == true && mounted) _refresh();
  }

  Future<void> _editUser(
    AppUser user,
    List<DepartmentRecord> departments,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditUserDialog(
        api: widget.api,
        user: user,
        departments: departments,
      ),
    );
    if (changed == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil pengguna berjaya dikemas kini.')),
      );
    }
  }

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/') && picture.contains(',')) {
      try {
        return MemoryImage(base64Decode(picture.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(picture);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Senarai Pengguna'),
        actions: [
          IconButton(
            tooltip: 'Muat semula',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_UserAdminData>(
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
          final data = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: data.users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = data.users[index];
              return Card(
                child: ListTile(
                  onTap: () => _editUser(user, data.departments),
                  leading: CircleAvatar(
                    backgroundImage: _imageProvider(user.profilePicture),
                    child: _imageProvider(user.profilePicture) == null
                        ? Text(user.nama.isEmpty ? '?' : user.nama[0])
                        : null,
                  ),
                  title: Text(
                    user.nama,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\n${user.jawatanPaparan} • ${user.jabatan}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit_rounded),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FutureBuilder<_UserAdminData>(
        future: _future,
        builder: (context, snapshot) => FloatingActionButton.extended(
          onPressed: snapshot.hasData
              ? () => _addUser(snapshot.data!.departments)
              : null,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Tambah Pengguna'),
        ),
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({
    required this.api,
    required this.user,
    required this.departments,
  });

  final ApiService api;
  final AppUser user;
  final List<DepartmentRecord> departments;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _noPkController;
  late String _jawatan;
  int? _departmentId;
  String? _newProfilePicture;
  bool _clearProfilePicture = false;
  bool _saving = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.nama);
    _noPkController = TextEditingController(text: widget.user.noPk);
    _jawatan = widget.user.jawatan;
    _departmentId = widget.user.departmentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noPkController.dispose();
    super.dispose();
  }

  String? _imageMimeType(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp') {
      return mime;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  ImageProvider<Object>? _previewImage() {
    final picture = _clearProfilePicture
        ? null
        : (_newProfilePicture ?? widget.user.profilePicture);
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/') && picture.contains(',')) {
      try {
        return MemoryImage(base64Decode(picture.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(picture);
  }

  Future<void> _pickProfilePicture() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;
      final mime = _imageMimeType(picked);
      if (mime == null) {
        setState(() => _error = 'Gunakan gambar JPEG, PNG atau WebP.');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > 500000) {
        setState(() => _error = 'Gambar terlalu besar. Pilih gambar lain yang lebih kecil.');
        return;
      }
      setState(() {
        _newProfilePicture = 'data:$mime;base64,${base64Encode(bytes)}';
        _clearProfilePicture = false;
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final nama = _nameController.text.trim();
    if (nama.length < 3 || _departmentId == null) {
      setState(() => _error = 'Lengkapkan nama dan Jabatan pengguna.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateAdminUser(
        userId: widget.user.id,
        nama: nama,
        jawatan: _jawatan,
        departmentId: _departmentId!,
        noPk: _noPkController.text.trim(),
        profilePicture: _newProfilePicture,
        clearProfilePicture: _clearProfilePicture,
      );
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
    final active = widget.departments.where((item) => item.active).toList();
    final preview = _previewImage();
    return AlertDialog(
      title: const Text('Edit Pengguna'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: preview,
                    child: preview == null
                        ? Text(
                            _nameController.text.trim().isEmpty
                                ? '?'
                                : _nameController.text.trim()[0],
                            style: const TextStyle(fontSize: 30),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: IconButton.filled(
                      tooltip: 'Tukar gambar profil',
                      onPressed: _picking ? null : _pickProfilePicture,
                      icon: _picking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _newProfilePicture = null;
                          _clearProfilePicture = true;
                        }),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Buang gambar profil'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nama Pengguna',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: widget.user.noKadPengenalan,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'No. Kad Pengenalan',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'ID login tidak diubah dari skrin ini.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noPkController,
                decoration: const InputDecoration(
                  labelText: 'No. PK',
                  prefixIcon: Icon(Icons.numbers_rounded),
                  helperText: 'Nombor pengawal untuk borang BPPA PKK 2.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _jawatan,
                decoration: const InputDecoration(
                  labelText: 'Jawatan',
                  prefixIcon: Icon(Icons.work_outline_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'Patrol', child: Text('Pengawal Rondaan')),
                  DropdownMenuItem(value: 'Supervisor', child: Text('Penyelia')),
                  DropdownMenuItem(value: 'Management', child: Text('Pengurusan')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _jawatan = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _departmentId,
                decoration: const InputDecoration(
                  labelText: 'Jabatan',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: active
                    .map(
                      (department) => DropdownMenuItem<int>(
                        value: department.id,
                        child: Text(department.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _departmentId = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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

class _UserAdminData {
  const _UserAdminData({required this.users, required this.departments});

  final List<AppUser> users;
  final List<DepartmentRecord> departments;
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog({required this.api, required this.departments});

  final ApiService api;
  final List<DepartmentRecord> departments;

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _nameController = TextEditingController();
  final _icController = TextEditingController();
  final _noPkController = TextEditingController();
  String _jawatan = 'Patrol';
  int? _departmentId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final active = widget.departments.where((item) => item.active).toList();
    if (active.isNotEmpty) _departmentId = active.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _icController.dispose();
    _noPkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final ic = _icController.text.replaceAll(RegExp(r'\D'), '');
    if (name.length < 3 || ic.length != 12 || _departmentId == null) {
      setState(() => _error = 'Lengkapkan nama, No. Kad Pengenalan 12 digit dan Jabatan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.createAdminUser(
        nama: name,
        noKadPengenalan: ic,
        jawatan: _jawatan,
        departmentId: _departmentId!,
        noPk: _noPkController.text.trim(),
      );
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
    final active = widget.departments.where((item) => item.active).toList();
    return AlertDialog(
      title: const Text('Tambah Pengguna'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nama',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _icController,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'No. Kad Pengenalan',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noPkController,
                decoration: const InputDecoration(
                  labelText: 'No. PK',
                  prefixIcon: Icon(Icons.numbers_rounded),
                  helperText: 'Nombor pengawal untuk borang BPPA PKK 2.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _jawatan,
                decoration: const InputDecoration(
                  labelText: 'Jawatan',
                  prefixIcon: Icon(Icons.work_outline_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'Patrol', child: Text('Pengawal Rondaan')),
                  DropdownMenuItem(
                    value: 'Supervisor',
                    child: Text('Penyelia'),
                  ),
                  DropdownMenuItem(
                    value: 'Management',
                    child: Text('Pengurusan'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _jawatan = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _departmentId,
                decoration: const InputDecoration(
                  labelText: 'Jabatan',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: active
                    .map(
                      (department) => DropdownMenuItem<int>(
                        value: department.id,
                        child: Text(department.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _departmentId = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
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
          child: Text(_saving ? 'Menyimpan…' : 'Tambah'),
        ),
      ],
    );
  }
}
