from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def update(path: Path, replacements):
    text = path.read_text(encoding='utf-8')
    original = text
    for old, new in replacements:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text, encoding='utf-8')
        print(f'updated {path.relative_to(ROOT)}')


# Bahasa Melayu rasmi untuk semua teks yang dipaparkan kepada pengguna.
dart_replacements = [
    ("'NFC + GPS live'", "'Imbas titik pemeriksaan dan rekod lokasi'"),
    ("'Sesi & checkpoint'", "'Sesi dan titik pemeriksaan'"),
    ("'Live operations'", "'Pemantauan operasi langsung'"),
    ("title: 'Admin'", "title: 'Pentadbiran'"),
    ("'OFFLINE READY'", "'SEDIA LUAR TALIAN'"),
    ("'AUTO SYNC • SYNCING'", "'PENYEGERAKAN AUTOMATIK • SEDANG DISEGERAKKAN'"),
    ("'AUTO SYNC • $pending PENDING'", "'PENYEGERAKAN AUTOMATIK • $pending MENUNGGU'"),
    ("'AUTO SYNC • READY'", "'PENYEGERAKAN AUTOMATIK • SEDIA'"),
    ("'AUTO SYNC • ${two(local.hour)}:${two(local.minute)}'", "'PENYEGERAKAN AUTOMATIK • ${two(local.hour)}:${two(local.minute)}'"),
    ("'$failed FAILED'", "'$failed GAGAL'"),
    ("'UJIAN ALARM'", "'UJIAN PENGGERA'"),
    ("'Test Alarm'", "'Uji Penggera'"),
    ("'Uji paparan penuh dan bunyi alarm.'", "'Uji paparan penuh dan bunyi penggera.'"),
    ("'Alarm / SOS'", "'Penggera / SOS'"),
    ("'Tutup alarm'", "'Tutup penggera'"),
    ("'Ini ialah ujian paparan dan bunyi alarm RimbaKawal.'", "'Ini ialah ujian paparan dan bunyi penggera RimbaKawal.'"),
    ("'Sesi baharu bermula. Lengkapkan checkpoint setiap $_sessionIntervalMinutes minit. Data rondaan disimpan lokal dahulu.'", "'Sesi baharu telah bermula. Lengkapkan semua titik pemeriksaan dalam tempoh sesi. Rekod rondaan akan disimpan pada peranti sebelum disegerakkan.'"),
    ("'Event selamat dalam telefon dan akan dihantar secara automatik apabila sambungan tersedia.'", "'Rekod SOS telah disimpan pada peranti dan akan dihantar secara automatik apabila sambungan tersedia.'"),
    ("'Aktifkan push notification'", "'Aktifkan pemberitahuan'"),
    ("'Push notification belum dikonfigurasi pada server aplikasi.'", "'Pemberitahuan belum dikonfigurasi pada pelayan aplikasi.'"),
    ("'Push notification RimbaKawal telah diaktifkan.'", "'Pemberitahuan RimbaKawal telah diaktifkan.'"),
    ("'Kebenaran notification belum diberikan pada peranti/browser ini.'", "'Kebenaran pemberitahuan belum diberikan pada peranti atau pelayar ini.'"),
    ("'LIVE • ±${position.accuracy.round()} m • ${_clock(now)}'", "'LANGSUNG • ±${position.accuracy.round()} m • ${_clock(now)}'"),
    ("'GPS tersedia • peta live menunggu internet • ±${position.accuracy.round()} m'", "'Lokasi tersedia • peta langsung menunggu sambungan internet • ±${position.accuracy.round()} m'"),
    ("'Konfigurasi rondaan belum pernah dimuat turun. Sambung internet sekali untuk menyediakan mod offline.'", "'Konfigurasi rondaan belum pernah dimuat turun. Sambungkan peranti ke Internet sekali untuk menyediakan penggunaan luar talian.'"),
    ("'Tag ini bukan checkpoint aktif untuk Jabatan anda.'", "'Tag ini bukan titik pemeriksaan aktif untuk Jabatan anda.'"),
    ("'Checkpoint seterusnya ialah ${next.name}.'", "'Titik pemeriksaan seterusnya ialah ${next.name}.'"),
    ("'${checkpoint.name} disimpan dalam telefon. Sync akan berlaku automatik.'", "'${checkpoint.name} telah disimpan pada peranti dan akan disegerakkan secara automatik.'"),
    ("'Insiden disimpan lokal dan dimasukkan ke barisan sync.'", "'Insiden telah disimpan pada peranti dan akan disegerakkan secara automatik.'"),
    ("'Guard confirmed OK'", "'Pengawal mengesahkan keadaan selamat'"),
    ("'Semua data sudah disimpan dalam telefon. ${_store.pendingCount(widget.user.id)} event masih menunggu sync.'", "'Semua data telah disimpan pada peranti. ${_store.pendingCount(widget.user.id)} rekod masih menunggu penyegerakan.'"),
    ("'Timeline sesi'", "'Rekod sesi'"),
    ("'STARTING'", "'MEMULAKAN'"),
    ("'ON PATROL'", "'SEDANG MERONDA'"),
    ("'LOCAL FIRST'", "'DISIMPAN PADA PERANTI'"),
    ("'SYNCING…'", "'MENYEGERAK…'"),
    ("'$pending PENDING'", "'$pending MENUNGGU'"),
    ("'Sync sekarang'", "'Segerak sekarang'"),
    ("'Tiada checkpoint aktif'", "'Tiada titik pemeriksaan aktif'"),
    ("'Semua checkpoint selesai'", "'Semua titik pemeriksaan selesai'"),
    ("'Sentuhkan tag NFC…'", "'Dekatkan tag pada peranti…'"),
    ("'Scan checkpoint'", "'Imbas titik pemeriksaan'"),
    ("'Data disimpan dalam telefon dahulu.'", "'Data akan disimpan pada peranti terlebih dahulu.'"),
    ("'Checkpoint dijangka: $nextName'", "'Titik pemeriksaan seterusnya: $nextName'"),
    ("'SCANNING…'", "'MENGIMBAS…'"),
    ("'SCAN MOCK NFC'", "'SIMULASI IMBASAN'"),
    ("'SCAN NFC'", "'IMBAS TITIK PEMERIKSAAN'"),
    ("'Checkpoint'", "'Titik Pemeriksaan'"),
    ("'Synced'", "'Disegerakkan'"),
    ("'Disimpan lokal'", "'Disimpan pada peranti'"),
    ("'Belum ada checkpoint dalam sesi ini.'", "'Belum ada titik pemeriksaan direkodkan dalam sesi ini.'"),
    ("'Refresh'", "'Muat semula'"),
    ("'MISSED CHECKPOINT'", "'TITIK PEMERIKSAAN TERLEPAS'"),
    ("'TIADA CHECKPOINT'", "'TIADA TITIK PEMERIKSAAN'"),
    ("'MISSING'", "'TERLEPAS'"),
    ("'Belum scan'", "'Belum diimbas'"),
    ("'${session.scannedCount}/${session.expectedCount} checkpoint direkodkan'", "'${session.scannedCount}/${session.expectedCount} titik pemeriksaan direkodkan'"),
    ("""'${history.department} • Sesi Rondaan setiap ${history.sessionIntervalMinutes} minit • semua anggota Jabatan'""", """'${history.department} • Sesi rondaan setiap ${history.sessionIntervalMinutes} minit • rekod mengikut sesi Jabatan'"""),
    ("'NFC tidak dipadankan'", "'Titik pemeriksaan tidak dikenal pasti'"),
    ("'Command Center'", "'Pusat Pemantauan'"),
    ("'Pantau patrol, late/missed session, SOS dan insiden secara live.'", "'Pantau rondaan, sesi terlepas, SOS dan insiden secara langsung.'"),
    ("'Jabatan & Checkpoint'", "'Jabatan dan Titik Pemeriksaan'"),
    ("'Selenggara Jabatan, kadar sesi dan NFC checkpoint dalam satu skrin.'", "'Selenggara Jabatan, kadar sesi dan titik pemeriksaan dalam satu skrin.'"),
    ("'Live Map'", "'Peta Langsung'"),
    ("'Status Guard'", "'Status Pengawal'"),
    ("label: Text('Alert')", "label: Text('Amaran')"),
    ("'Tiada guard dalam kategori ini.'", "'Tiada pengawal dalam kategori ini.'"),
    ("'Incident Queue'", "'Senarai Insiden'"),
    ("'${incidents.length} belum resolved'", "'${incidents.length} belum diselesaikan'"),
    ("'${sos.length} event'", "'${sos.length} rekod'"),
    ("'Operations Command Center'", "'Pusat Pemantauan Operasi'"),
    ("'Auto-refresh 8 saat${generatedAt == null ? '' : ' • ${_clock(generatedAt!)}'}'", "'Kemas kini automatik setiap 8 saat${generatedAt == null ? '' : ' • ${_clock(generatedAt!)}'}'"),
    ("'COMPLETE'", "'LENGKAP'"),
    ("'PATROLLING'", "'SEDANG MERONDA'"),
    ("'LATE'", "'LEWAT'"),
    ("'MISSED'", "'TERLEPAS'"),
    ("'NO CHECKPOINT'", "'TIADA TITIK PEMERIKSAAN'"),
    ("'WAITING'", "'MENUNGGU'"),
    ("'GUARD'", "'PENGAWAL'"),
    ("'Admin'", "'Pentadbiran'"),
]

for dart_file in (ROOT / 'lib').rglob('*.dart'):
    update(dart_file, dart_replacements)

# Beberapa ayat pelayan turut dipaparkan terus kepada pengguna.
worker_replacements = [
    ("'Event tempatan tidak sah.'", "'Rekod tempatan tidak sah.'"),
    ("'Jenis event tidak disokong.'", "'Jenis rekod tidak disokong.'"),
    ("'Event gagal diproses.'", "'Rekod gagal diproses.'"),
    ("`Checkpoint seterusnya ialah ${next.name}.`", "`Titik pemeriksaan seterusnya ialah ${next.name}.`"),
    ("'Checkpoint insiden tidak sah.'", "'Titik pemeriksaan insiden tidak sah.'"),
    ("'INSIDEN URGENT'", "'INSIDEN SEGERA'"),
    ("'Welfare Perlu Perhatian'", "'Kebajikan Perlu Perhatian'"),
    ("'Status welfare tidak sah.'", "'Status kebajikan tidak sah.'"),
    ("'NFC ini tidak berdaftar sebagai checkpoint untuk Jabatan anda.'", "'Tag ini tidak berdaftar sebagai titik pemeriksaan untuk Jabatan anda.'"),
    ("`Susunan rondaan aktif. Checkpoint seterusnya ialah ${expected.name}.`", "`Susunan rondaan aktif. Titik pemeriksaan seterusnya ialah ${expected.name}.`"),
]
for js_file in (ROOT / 'worker').glob('*.js'):
    update(js_file, worker_replacements)

# Sejarah rondaan: satu rekod bagi setiap sesi Jabatan, bukan satu rekod bagi
# setiap pengawal. Siapa yang mengimbas akan menjadi pengawal bagi sesi itu.
index_path = ROOT / 'worker' / 'index.js'
index_text = index_path.read_text(encoding='utf-8')
get_scans_start = index_text.index('async function getScans')

member_start = index_text.find('  const memberResult = await env.DB.prepare(', get_scans_start)
scan_start = index_text.find('  const scanResult = await env.DB.prepare(', get_scans_start)
if member_start != -1 and scan_start != -1 and member_start < scan_start:
    index_text = index_text[:member_start] + index_text[scan_start:]

get_scans_start = index_text.index('async function getScans')
sessions_start = index_text.index('  if (!isFutureDay) {', get_scans_start)
sessions_end = index_text.index('\n\n  return json({', sessions_start)
new_sessions = """  if (!isFutureDay) {
    const sessionCount = Math.ceil(1440 / interval);
    for (let index = 0; index < sessionCount; index += 1) {
      const startMs = bounds.startMs + index * interval * 60000;
      const endMs = Math.min(bounds.endMs, startMs + interval * 60000);
      if (requestedDate === todayKey && startMs > nowMs) break;

      const sessionScans = scans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= startMs && time < endMs;
      });
      const scannedCheckpointIds = new Set(
        sessionScans
          .map((scan) => Number(scan.checkpoint_id || 0))
          .filter((id) => id > 0),
      );
      const missing = checkpoints.filter(
        (checkpoint) => !scannedCheckpointIds.has(Number(checkpoint.id)),
      );

      let status = 'in_progress';
      if (checkpoints.length === 0) status = 'no_checkpoints';
      else if (missing.length === 0) status = 'complete';
      else if (isPastDay || endMs <= nowMs) status = 'missed';

      const scannerIds = [...new Set(
        sessionScans.map((scan) => Number(scan.user_id || 0)).filter((id) => id > 0),
      )];
      const scannerNames = [...new Set(
        sessionScans.map((scan) => String(scan.user_name || '').trim()).filter(Boolean),
      )];
      const firstScan = sessionScans[0] ?? null;

      sessions.push({
        userId: scannerIds.length === 1 ? scannerIds[0] : 0,
        userName: scannerNames.length > 0
          ? scannerNames.join(', ')
          : 'Tiada pengawal direkodkan',
        profilePicture: scannerIds.length === 1 ? (firstScan?.profile_picture || null) : null,
        index,
        startAt: new Date(startMs).toISOString(),
        endAt: new Date(endMs).toISOString(),
        status,
        expectedCount: checkpoints.length,
        scannedCount: scannedCheckpointIds.size,
        missingCheckpoints: missing.map((checkpoint) => ({
          id: checkpoint.id,
          name: checkpoint.name,
          position: checkpoint.position,
        })),
        scans: sessionScans.map(scanJson),
      });
    }
    sessions.sort((left, right) => Date.parse(right.startAt) - Date.parse(left.startAt));
  }"""
index_text = index_text[:sessions_start] + new_sessions + index_text[sessions_end:]
index_path.write_text(index_text, encoding='utf-8')
print('updated worker/index.js session history logic')

# Pusat Pemantauan: pengawal yang tidak terlibat dalam sesuatu sesi tidak
# boleh dianggap lewat atau terlepas. Hanya pengawal yang benar-benar memulakan
# rondaan atau mempunyai imbasan dalam sesi dinilai.
app_path = ROOT / 'worker' / 'app.js'
app_text = app_path.read_text(encoding='utf-8')
cc_start = app_text.index('async function commandCenter')
missed_start = app_text.index('    let missedSessions = 0;', cc_start)
minutes_start = app_text.index('    const minutesIntoSession', missed_start)
new_missed = """    let missedSessions = 0;
    for (let index = 0; index < currentIndex; index += 1) {
      const previousStartMs = scheduleDay.startMs + index * interval * 60000;
      const previousEndMs = Math.min(
        scheduleDay.endMs,
        previousStartMs + interval * 60000,
      );
      const previousRows = userDayScans.filter((row) => {
        const time = Date.parse(row.scanned_at);
        return time >= previousStartMs && time < previousEndMs;
      });
      if (previousRows.length === 0) continue;
      const unique = new Set(
        previousRows
          .map((row) => Number(row.checkpoint_id))
          .filter((id) => id > 0),
      );
      if (expected > 0 && unique.size < expected) missedSessions += 1;
    }

"""
app_text = app_text[:missed_start] + new_missed + app_text[minutes_start:]

cc_start = app_text.index('async function commandCenter')
status_start = app_text.index("    let status = 'waiting';", cc_start)
status_end = app_text.index("\n\n    if (status === 'complete')", status_start)
new_status = """    let status = 'waiting';
    if (expected === 0) status = 'no_checkpoints';
    else if (uniqueCurrent.size >= expected) status = 'complete';
    else if (activePatrol && minutesIntoSession >= grace && uniqueCurrent.size === 0) status = 'late';
    else if (activePatrol || uniqueCurrent.size > 0) status = 'patrolling';
    else if (missedSessions > 0) status = 'missed';"""
app_text = app_text[:status_start] + new_status + app_text[status_end:]
app_path.write_text(app_text, encoding='utf-8')
print('updated worker/app.js command center missed logic')

# Nombor versi aplikasi.
pubspec = ROOT / 'pubspec.yaml'
pub_text = pubspec.read_text(encoding='utf-8')
pub_text = re.sub(r'^version:\s*[^\n]+$', 'version: 0.4.1+5', pub_text, flags=re.M)
pubspec.write_text(pub_text, encoding='utf-8')
print('updated pubspec.yaml version')

# Audit ringkas frasa UI lama. Tidak menggagalkan proses kerana sesetengah
# perkataan mungkin wujud sebagai nama teknikal dalaman, tetapi hasilnya akan
# kelihatan dalam log CI untuk semakan.
patterns = re.compile(r"NFC \+ GPS live|Live operations|OFFLINE READY|AUTO SYNC|FAILED|STARTING|ON PATROL|LOCAL FIRST|SYNCING|PENDING|Scan checkpoint|SCANNING|SCAN NFC|MISSED CHECKPOINT|Belum scan|Command Center|Status Guard|Incident Queue|Operations Command Center|Auto-refresh|NO CHECKPOINT|WAITING")
remaining = []
for dart_file in (ROOT / 'lib').rglob('*.dart'):
    for line_no, line in enumerate(dart_file.read_text(encoding='utf-8').splitlines(), 1):
        if patterns.search(line):
            remaining.append(f'{dart_file.relative_to(ROOT)}:{line_no}: {line.strip()}')
if remaining:
    print('Frasa lama yang masih dikesan:')
    print('\n'.join(remaining))
else:
    print('Audit frasa UI lama: bersih')
