import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.user, required this.api, super.key});

  final AppUser user;
  final ApiService api;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late AppUser _user;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gunakan gambar JPEG, PNG atau WebP.')),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > 500000) {
        throw const ApiException(
          'Gambar masih terlalu besar selepas pemampatan. Cuba gambar lain.',
        );
      }
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      final updated = await widget.api.updateProfilePicture(dataUrl);
      if (!mounted) return;
      setState(() => _user = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gambar profil berjaya dikemas kini.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
    final image = _imageProvider(_user.profilePicture);
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundImage: image,
                  child: image == null
                      ? Text(
                          _user.nama.isEmpty ? '?' : _user.nama[0],
                          style: const TextStyle(fontSize: 36),
                        )
                      : null,
                ),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: IconButton.filled(
                    tooltip: 'Muat naik gambar profil',
                    onPressed: _uploading ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_a_photo_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Tekan ikon kamera untuk memilih gambar profil.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _InfoTile(label: 'Nama', value: _user.nama),
          _InfoTile(label: 'No. Kad Pengenalan', value: _user.noKadPengenalan),
          _InfoTile(
            label: 'No. PK',
            value: _user.noPk.isEmpty ? '-' : _user.noPk,
          ),
          _InfoTile(label: 'Jawatan', value: _user.jawatanPaparan),
          _InfoTile(label: 'Sekolah', value: _user.jabatan),
          _InfoTile(
            label: 'Kadar Sesi Rondaan',
            value: 'Setiap ${_user.sessionIntervalMinutes} minit',
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    );
  }
}
