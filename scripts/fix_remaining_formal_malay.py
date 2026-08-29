from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace_values(path: Path, values: dict[str, str]) -> None:
    text = path.read_text(encoding='utf-8')
    changed = False
    for old, new in values.items():
        if old in text:
            text = text.replace(old, new)
            changed = True
        elif new not in text:
            raise SystemExit(
                f'Frasa sasaran atau penggantinya tidak ditemui dalam '
                f'{path.relative_to(root)}: {old}'
            )
    if changed:
        path.write_text(text, encoding='utf-8')
        print(f'Dikemas kini: {path.relative_to(root)}')
    else:
        print(f'Sudah dikemas kini: {path.relative_to(root)}')


# Kekalkan nilai peranan dalaman dalam Bahasa Inggeris untuk keserasian API,
# tetapi semua paparan kepada pengguna menggunakan Bahasa Melayu rasmi.
app_user = root / 'lib/core/api/app_user.dart'
text = app_user.read_text(encoding='utf-8')
if 'String get jawatanPaparan =>' not in text:
    marker = "  bool get canMonitor => isManagement || isSupervisor;\n"
    if marker not in text:
        raise SystemExit('Lokasi getter jawatanPaparan tidak ditemui.')
    text = text.replace(
        marker,
        marker + "  String get jawatanPaparan => labelJawatan(jawatan);\n",
    )
if 'String labelJawatan(String? value)' not in text:
    text = text.rstrip() + """

String labelJawatan(String? value) {
  final raw = (value ?? '').trim();
  return switch (raw.toLowerCase()) {
    'management' => 'Pengurusan',
    'supervisor' => 'Penyelia',
    'patrol' => 'Pengawal Rondaan',
    _ => raw.isEmpty ? '-' : raw,
  };
}
"""
app_user.write_text(text, encoding='utf-8')
print('Disahkan: label jawatan rasmi')


replacements = {
    root / 'lib/features/profile/profile_screen.dart': {
        "AppBar(title: const Text('Profile'))": "AppBar(title: const Text('Profil'))",
        "tooltip: 'Upload gambar profil'": "tooltip: 'Muat naik gambar profil'",
        "value: _user.jawatan)": "value: _user.jawatanPaparan)",
    },
    root / 'lib/features/dashboard/dashboard_screen.dart': {
        "Text('${_user.jawatan} • ${_user.jabatan}')":
            "Text('${_user.jawatanPaparan} • ${_user.jabatan}')",
        "subtitle: _user.jawatan,": "subtitle: _user.jawatanPaparan,",
    },
    root / 'lib/features/admin/user_maintenance_screen.dart': {
        "'${user.noKadPengenalan}\\n${user.jawatan} • ${user.jabatan}'":
            "'${user.noKadPengenalan}\\n${user.jawatanPaparan} • ${user.jabatan}'",
        "'Lengkapkan nama, IC 12 digit dan Jabatan.'":
            "'Lengkapkan nama, No. Kad Pengenalan 12 digit dan Jabatan.'",
        "DropdownMenuItem(value: 'Patrol', child: Text('Patrol'))":
            "DropdownMenuItem(value: 'Patrol', child: Text('Pengawal Rondaan'))",
        "child: Text('Supervisor'),": "child: Text('Penyelia'),",
        "child: Text('Management'),": "child: Text('Pengurusan'),",
    },
    root / 'lib/features/admin/department_maintenance_screen.dart': {
        "'${department.checkpointCount} checkpoint aktif'":
            "'${department.checkpointCount} titik pemeriksaan aktif'",
        "Text('Belum ada checkpoint NFC.')": "Text('Belum ada titik pemeriksaan.')",
        "label: const Text('Tambah Checkpoint')":
            "label: const Text('Tambah Titik Pemeriksaan')",
        "helperText: 'Default: 120 minit (2 jam)'":
            "helperText: 'Nilai asal: 120 minit (2 jam)'",
        "'Lengkapkan nama, UID NFC dan susunan checkpoint.'":
            "'Lengkapkan nama, UID tag NFC dan susunan titik pemeriksaan.'",
        "widget.checkpoint == null ? 'Tambah Checkpoint' : 'Edit Checkpoint'":
            "widget.checkpoint == null ? 'Tambah Titik Pemeriksaan' : 'Edit Titik Pemeriksaan'",
        "labelText: 'Nama checkpoint'": "labelText: 'Nama titik pemeriksaan'",
        "hintText: 'Contoh: Checkpoint 1'": "hintText: 'Contoh: Pintu Utama'",
        "labelText: 'NFC UID'": "labelText: 'UID tag NFC'",
        "hintText: 'Scan atau masukkan UID'": "hintText: 'Imbas tag atau masukkan UID'",
        "label: Text(_scanning ? 'Scan…' : 'Scan')":
            "label: Text(_scanning ? 'Mengimbas…' : 'Imbas')",
        "'Web menggunakan Mock NFC untuk ujian setup.'":
            "'Versi web menggunakan simulasi NFC untuk ujian konfigurasi.'",
        "labelText: 'Susunan checkpoint'": "labelText: 'Susunan titik pemeriksaan'",
        "title: const Text('Checkpoint aktif')":
            "title: const Text('Titik pemeriksaan aktif')",
    },
    root / 'lib/features/admin/report_screen.dart': {
        "'Jumlah scan'": "'Jumlah imbasan'",
        "'Rekod Checkpoint'": "'Rekod Titik Pemeriksaan'",
        "'Tiada rekod scan dalam tempoh ini.'":
            "'Tiada rekod imbasan dalam tempoh ini.'",
        "'Dijana oleh RimbaKawal. Masa rekod checkpoint datang daripada server.'":
            "'Dijana oleh RimbaKawal. Masa rekod titik pemeriksaan diperoleh daripada pelayan.'",
        "'Pilih Jabatan dan julat sehingga 31 hari. PDF merangkumi rekod checkpoint dan event SOS.'":
            "'Pilih Jabatan dan julat sehingga 31 hari. PDF merangkumi rekod titik pemeriksaan dan kejadian SOS.'",
    },
    root / 'lib/features/admin/command_center_screen.dart': {
        "SnackBar(content: Text('Insiden ditukar kepada ${status.toUpperCase()}.'),)":
            "SnackBar(content: Text('Status insiden ditukar kepada ${_incidentStatusLabel(status)}.'),)",
        "label: 'ALERT'": "label: 'AMARAN'",
        "label: 'INCIDENT'": "label: 'INSIDEN'",
        "label: 'URGENT'": "label: 'SEGERA'",
        "label: 'SOS 24H'": "label: 'SOS 24 JAM'",
        "'$scanned/$expected checkpoint • last scan $time${missed > 0 ? ' • $missed missed' : ''}'":
            "'$scanned/$expected titik pemeriksaan • imbasan terakhir $time${missed > 0 ? ' • $missed sesi terlepas' : ''}'",
        "'${incident['category'] ?? 'Incident'} • ${severity.toUpperCase()}'":
            "'${incident['category'] ?? 'Insiden'} • ${_incidentSeverityLabel(severity)}'",
        "'${incident['nama'] ?? '-'} • ${incident['jabatan'] ?? '-'} • ${incident['checkpoint_name'] ?? 'Tanpa checkpoint'}'":
            "'${incident['nama'] ?? '-'} • ${incident['jabatan'] ?? '-'} • ${incident['checkpoint_name'] ?? 'Tanpa titik pemeriksaan'}'",
        "status.toUpperCase(),": "_incidentStatusLabel(status),",
        "label: const Text('Acknowledge')": "label: const Text('Ambil Maklum')",
        "label: const Text('Resolve')": "label: const Text('Selesaikan')",
    },
    root / 'lib/features/admin/live_patrol_map_screen.dart': {
        "'live' => 'LIVE',": "'live' => 'LANGSUNG',",
        "'delayed' => 'DELAYED',": "'delayed' => 'TERTUNDA',",
        "'stale' => 'STALE',": "'stale' => 'TIDAK TERKINI',",
        "_ => 'WAITING GPS',": "_ => 'MENUNGGU LOKASI',",
        "text: 'GPS ${_time(patrol['locationAt'])}'":
            "text: 'Lokasi ${_time(patrol['locationAt'])}'",
        "text: '${_trail(patrol).length} titik trail'":
            "text: '${_trail(patrol).length} titik laluan'",
        "'Rondaan telah bermula tetapi telefon belum menghantar koordinat GPS. Semak permission lokasi pada telefon guard.'":
            "'Rondaan telah bermula tetapi telefon belum menghantar koordinat lokasi. Semak kebenaran lokasi pada telefon pengawal.'",
        "title: const Text('Live Patrol Map')": "title: const Text('Peta Rondaan Langsung')",
        "tooltip: 'Fit semua guard'": "tooltip: 'Papar semua pengawal'",
        "'OpenStreetMap contributors'": "'Penyumbang OpenStreetMap'",
        "'$total rondaan aktif • $located ada GPS'":
            "'$total rondaan aktif • $located mempunyai lokasi'",
        "'Refresh 5s${generatedAt == null ? '' : ' • ${_headerTime(generatedAt!)}'}'":
            "'Kemas kini setiap 5 saat${generatedAt == null ? '' : ' • ${_headerTime(generatedAt!)}'}'",
        "? 'GPS ${patrol['locationAgeSeconds'] ?? 0}s ago'":
            "? 'Lokasi ${patrol['locationAgeSeconds'] ?? 0} saat lalu'",
        ": 'Sesi aktif • menunggu GPS'": ": 'Sesi aktif • menunggu lokasi'",
    },
    root / 'lib/features/admin/sos_management_screen.dart': {
        "import 'package:flutter/material.dart';\n":
            "import 'package:flutter/material.dart';\n\nimport '../../core/api/app_user.dart';\n",
        "'$active SOS ACTIVE'": "'$active SOS AKTIF'",
        "label: Text(isActive ? 'ACTIVE' : 'SELESAI')":
            "label: Text(isActive ? 'AKTIF' : 'SELESAI')",
        "'${event['jawatan'] ?? '-'} • ${event['jabatan'] ?? '-'}'":
            "'${labelJawatan(event['jawatan'] as String?)} • ${event['jabatan'] ?? '-'}'",
    },
    root / 'lib/features/sos/sos_alert_gate.dart': {
        "'ALERT SOS JABATAN'": "'AMARAN SOS JABATAN'",
        "value: event['jawatan'] as String? ?? '-'":
            "value: labelJawatan(event['jawatan'] as String?)",
        "'SOS ini masih ACTIVE sehingga Supervisor atau Management menandakan ia selesai.'":
            "'SOS ini kekal AKTIF sehingga Penyelia atau Pengurusan menandakannya selesai.'",
        "label: const Text('TUTUP ALERT')": "label: const Text('TUTUP AMARAN')",
        "hintText: 'Contoh: Guard telah ditemui dan keadaan disahkan selamat.'":
            "hintText: 'Contoh: Pengawal telah ditemui dan keadaan disahkan selamat.'",
    },
    root / 'lib/features/patrol/patrol_screen.dart': {
        "DropdownMenuItem(value: 'normal', child: Text('Normal'))":
            "DropdownMenuItem(value: 'normal', child: Text('Biasa'))",
    },
    root / 'web/manifest.json': {
        '"description": "RimbaKawal smart patrol system."':
            '"description": "RimbaKawal — Sistem Rondaan Pintar."',
    },
    root / 'web/index.html': {
        'content="RimbaKawal smart patrol system."':
            'content="RimbaKawal — Sistem Rondaan Pintar."',
    },
}

for path, values in replacements.items():
    replace_values(path, values)


# Tambah pemetaan status/keutamaan insiden untuk paparan sahaja. Nilai API
# seperti open, acknowledged, resolved, urgent dan important kekal tidak berubah.
command_center = root / 'lib/features/admin/command_center_screen.dart'
text = command_center.read_text(encoding='utf-8')
if 'String _incidentStatusLabel(String status)' not in text:
    text = text.rstrip() + """

String _incidentStatusLabel(String status) => switch (status.toLowerCase()) {
      'open' => 'TERBUKA',
      'acknowledged' => 'DIAMBIL MAKLUM',
      'resolved' => 'SELESAI',
      _ => status.toUpperCase(),
    };

String _incidentSeverityLabel(String severity) => switch (severity.toLowerCase()) {
      'urgent' => 'SEGERA',
      'important' => 'PENTING',
      'normal' => 'BIASA',
      _ => severity.toUpperCase(),
    };
"""
    command_center.write_text(text, encoding='utf-8')
    print('Ditambah: pemetaan paparan insiden rasmi')
else:
    print('Disahkan: pemetaan paparan insiden rasmi')


# Audit frasa paparan yang sepatutnya sudah tiada. Corak ini sengaja khusus
# supaya nilai dalaman API dan nama kelas teknikal tidak dianggap kesalahan.
audit_terms = {
    "const Text('Profile')",
    "tooltip: 'Upload gambar profil'",
    "Text('Patrol')",
    "Text('Supervisor')",
    "Text('Management')",
    " checkpoint aktif'",
    "Text('Belum ada checkpoint NFC.')",
    "Text('Tambah Checkpoint')",
    "'Tambah Checkpoint'",
    "'Edit Checkpoint'",
    "labelText: 'Nama checkpoint'",
    "hintText: 'Scan atau masukkan UID'",
    "'Web menggunakan Mock NFC untuk ujian setup.'",
    "labelText: 'Susunan checkpoint'",
    "Text('Checkpoint aktif')",
    "'Jumlah scan'",
    "'Rekod Checkpoint'",
    "'Tiada rekod scan dalam tempoh ini.'",
    "rekod checkpoint datang daripada server",
    "rekod checkpoint dan event SOS",
    "label: 'ALERT'",
    "label: 'INCIDENT'",
    "label: 'URGENT'",
    "label: 'SOS 24H'",
    "checkpoint • last scan",
    "missed' : ''",
    "Text('Acknowledge')",
    "Text('Resolve')",
    "'Live Patrol Map'",
    "'Fit semua guard'",
    "titik trail",
    "permission lokasi pada telefon guard",
    "'Refresh 5s",
    "s ago'",
    "menunggu GPS",
    "SOS ACTIVE",
    "? 'ACTIVE' : 'SELESAI'",
    "'ALERT SOS JABATAN'",
    "'TUTUP ALERT'",
    "Contoh: Guard telah ditemui",
    "RimbaKawal smart patrol system.",
    "NFC + GPS live",
    "Live operations",
    "WAITING GPS",
    "Auto-refresh",
    "OFFLINE READY",
    "AUTO SYNC",
    "MISSED CHECKPOINT",
    "Command Center",
    "Status Guard",
    "Incident Queue",
    "Operations Command Center",
}
remaining = []
for path in list((root / 'lib').rglob('*.dart')) + [
    root / 'web/manifest.json',
    root / 'web/index.html',
]:
    text = path.read_text(encoding='utf-8')
    for term in audit_terms:
        if term in text:
            remaining.append(f'{path.relative_to(root)} -> {term}')
if remaining:
    raise SystemExit('Istilah paparan lama masih ditemui:\n' + '\n'.join(sorted(remaining)))
print('Audit Bahasa Melayu rasmi: bersih')
