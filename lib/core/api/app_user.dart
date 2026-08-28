class AppUser {
  const AppUser({
    required this.id,
    required this.nama,
    required this.noKadPengenalan,
    required this.jawatan,
    required this.jabatan,
    required this.profilePicture,
    this.active = true,
  });

  final int id;
  final String nama;
  final String noKadPengenalan;
  final String jawatan;
  final String jabatan;
  final String? profilePicture;
  final bool active;

  bool get isManagement => jawatan.toLowerCase() == 'management';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num).toInt(),
      nama: json['nama'] as String,
      noKadPengenalan: json['noKadPengenalan'] as String,
      jawatan: json['jawatan'] as String,
      jabatan: json['jabatan'] as String,
      profilePicture: json['profilePicture'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }
}
