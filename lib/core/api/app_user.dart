class AppUser {
  const AppUser({
    required this.id,
    required this.nama,
    required this.noKadPengenalan,
    required this.jawatan,
    required this.jabatan,
    required this.profilePicture,
    required this.departmentId,
    required this.sessionIntervalMinutes,
    this.active = true,
  });

  final int id;
  final String nama;
  final String noKadPengenalan;
  final String jawatan;
  final String jabatan;
  final String? profilePicture;
  final int? departmentId;
  final int sessionIntervalMinutes;
  final bool active;

  bool get isManagement => jawatan.toLowerCase() == 'management';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num).toInt(),
      nama: json['nama'] as String,
      noKadPengenalan: json['noKadPengenalan'] as String,
      jawatan: json['jawatan'] as String,
      jabatan: json['jabatan'] as String? ?? 'Belum ditetapkan',
      profilePicture: json['profilePicture'] as String?,
      departmentId: (json['departmentId'] as num?)?.toInt(),
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      active: json['active'] as bool? ?? true,
    );
  }
}
