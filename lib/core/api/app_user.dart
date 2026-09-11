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
    this.noPk = '',
    this.guardStatus = 'Tetap',
    this.active = true,
    this.companyId,
    this.companyName = '',
  });

  final int id;
  final String nama;
  final String noKadPengenalan;
  final String jawatan;
  final String jabatan;
  final String? profilePicture;
  final int? departmentId;
  final int? companyId;
  final String companyName;
  final int sessionIntervalMinutes;
  final int sessionStartMinutes;
  final String noPk;
  final String guardStatus;
  final bool active;

  bool get isManagement => jawatan.toLowerCase() == 'management';
  bool get isAdministration => jawatan.toLowerCase() == 'administration';
  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';
  bool get canMonitor => isManagement || isSupervisor;
  bool get canDownloadReports => isManagement || isAdministration;
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
      companyId: (json['companyId'] as num?)?.toInt(),
      companyName: json['companyName'] as String? ?? '',
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      sessionStartMinutes:
          (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,
      noPk: json['noPk'] as String? ?? '',
      guardStatus: json['guardStatus'] as String? ?? 'Tetap',
      active: json['active'] as bool? ?? true,
    );
  }
}

String labelJawatan(String? value) {
  final raw = (value ?? '').trim();
  return switch (raw.toLowerCase()) {
    'management' => 'Admin Sistem',
    'administration' => 'Pentadbiran Syarikat',
    'supervisor' => 'Penyelia',
    'patrol' => 'Pengawal Rondaan',
    _ => raw.isEmpty ? '-' : raw,
  };
}
