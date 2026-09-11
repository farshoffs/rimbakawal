# ZPatrol - Matriks Akses & Hierarki Syarikat

## Hierarki baharu

`Admin Sistem -> Syarikat -> Banyak Sekolah -> Penyelia / Pengawal Rondaan`

Satu syarikat boleh mengendalikan banyak sekolah. Nama syarikat pada tetapan Sekolah dinormalisasikan kepada rekod `companies`, setiap sekolah mempunyai `company_id`, dan pengguna mewarisi `company_id` daripada sekolah utama mereka.

## Peranan

| Peranan | Kod | Skop |
| --- | --- | --- |
| Admin Sistem | `Management` | Akses penuh merentas semua syarikat dan sekolah. |
| Pentadbiran Syarikat | `Administration` | Laporan PDF sahaja untuk semua sekolah di bawah syarikat yang sama. |
| Penyelia | `Supervisor` | Operasi dan pemantauan sekolah sendiri. |
| Pengawal Rondaan | `Patrol` | Operasi rondaan sekolah sendiri. |

## Pentadbiran Syarikat

- Log masuk terus ke dashboard laporan khas.
- Boleh melihat senarai semua sekolah yang berkongsi `company_id` yang sama.
- Boleh memilih mana-mana sekolah tersebut dan menjana PKK 2, PKK 3 atau PKK 4.
- Backend mengesahkan bahawa `department_id` laporan benar-benar berada di bawah `company_id` akaun tersebut.
- API operasi lain kekal disekat.

## Sekatan akaun

Hanya `Management` boleh memanggil `PUT /api/admin/users/:id/status`. Menyekat akaun menetapkan `active = 0` dan memadam sesi aktif pengguna. Login dan sesi sedia ada ditolak sehingga Admin Sistem menyahsekat akaun.
