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
    this.sessionStartMinutes = 420,
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
  final int sessionStartMinutes;
  final bool active;

  bool get isManagement => jawatan.toLowerCase() == 'management';
  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';
  bool get canMonitor => isManagement || isSupervisor;
  String get jawatanPaparan => labelJawatan(jawatan);

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
      sessionStartMinutes:
          (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,
      active: json['active'] as bool? ?? true,
    );
  }
}

String labelJawatan(String? value) {
  final raw = (value ?? '').trim();
  return switch (raw.toLowerCase()) {
    'management' => 'Pengurusan',
    'supervisor' => 'Penyelia',
    'patrol' => 'Pengawal Rondaan',
    _ => raw.isEmpty ? '-' : raw,
  };
}
