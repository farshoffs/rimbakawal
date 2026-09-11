# ZPatrol - Matriks Akses Pengguna

| Peranan | Kod | Skop |
| --- | --- | --- |
| Admin Sistem | `Management` | Pentadbiran penuh sistem merentas lokasi. |
| Pentadbiran Syarikat | `Administration` | Laporan PDF sahaja untuk lokasi sendiri. |
| Penyelia | `Supervisor` | Operasi rondaan dan pemantauan lokasi sendiri. |
| Pengawal Rondaan | `Patrol` | Operasi rondaan harian. |

## Akses utama

- **Admin Sistem**: semua fungsi, konfigurasi lokasi/checkpoint, pengguna, pemantauan, kehadiran, SOS/insiden, laporan PDF, dan sekat/nyahsekat akaun pengguna.
- **Pentadbiran Syarikat**: hanya laporan PDF PKK 2, PKK 3 dan PKK 4 bagi lokasi yang dipautkan. Endpoint operasi disekat di server.
- **Penyelia**: Mula Rondaan, Kehadiran, Sejarah, Profil dan Pusat Pemantauan lokasi sendiri. Tiada konfigurasi Admin Sistem dan tiada laporan PDF pentadbiran.
- **Pengawal Rondaan**: Mula Rondaan, Kehadiran, Sejarah dan Profil. Tiada Pemantauan, Pentadbiran atau laporan PDF pentadbiran.

## Sekatan akaun

Hanya `Management` boleh memanggil `PUT /api/admin/users/:id/status`. Menyekat akaun menetapkan `active = 0` dan memadam semua sesi aktif pengguna tersebut. Login dan semua sesi sedia ada akan ditolak sehingga Admin Sistem menyahsekat akaun.
