import 'dart:io';

import 'package:rimbakawal/features/admin/pkk_pdf_generator.dart';

Future<void> main() async {
  final data = <String, dynamic>{
    'department': <String, dynamic>{
      'id': 1,
      'name': 'SK ANAK-ANAK ANGKATAN TENTERA',
      'companyName': 'ACTIVE NETWORK SECURITY SERVICES SDN BHD',
      'zone': 'KUBANG PASU 7',
      'state': 'KEDAH',
    },
    'guards': <Map<String, dynamic>>[
      {
        'id': 1,
        'nama': 'AHMAD NOZAL BIN MOHD ZAN',
        'no_pk': '1',
        'jawatan': 'patrol',
      },
      {
        'id': 2,
        'nama': 'MUHAMAD ABDUL BASHER SHAM BIN ABDUL MUKTI',
        'no_pk': '2',
        'jawatan': 'patrol',
      },
      {
        'id': 3,
        'nama': 'MOHD AMIRUL ASHRAF BIN ABDUL WAHAB',
        'no_pk': '3',
        'jawatan': 'patrol',
      },
      {'id': 4, 'nama': 'OMAR BIN ISMAIL', 'no_pk': '4', 'jawatan': 'patrol'},
    ],
    'checkpoints': <Map<String, dynamic>>[
      {'id': 1, 'name': 'CP1', 'position': 1},
      {'id': 2, 'name': 'CP2', 'position': 2},
      {'id': 3, 'name': 'CP3', 'position': 3},
      {'id': 4, 'name': 'CP4', 'position': 4},
    ],
  };

  final attendance = <Map<String, dynamic>>[];
  void punch(
    int userId,
    String name,
    int day,
    int inHour,
    int inMinute,
    int outDay,
    int outHour,
    int outMinute,
  ) {
    attendance
      ..add({
        'user_id': userId,
        'nama': name,
        'no_pk': '$userId',
        'jawatan': 'patrol',
        'punch_type': 'IN',
        'punched_at': _utcIso(2025, 11, day, inHour, inMinute),
      })
      ..add({
        'user_id': userId,
        'nama': name,
        'no_pk': '$userId',
        'jawatan': 'patrol',
        'punch_type': 'OUT',
        'punched_at': _utcIso(
          outDay == 1 ? 2025 : 2025,
          outDay == 1 ? 12 : 11,
          outDay,
          outHour,
          outMinute,
        ),
      });
  }

  for (var day = 10; day <= 30; day++) {
    if (day.isEven) {
      punch(1, 'AHMAD NOZAL BIN MOHD ZAN', day, 6, 49, day, 19, 1);
      punch(3, 'MOHD AMIRUL ASHRAF BIN ABDUL WAHAB', day, 6, 52, day, 19, 2);
    } else {
      final outDay = day == 30 ? 1 : day + 1;
      punch(
        2,
        'MUHAMAD ABDUL BASHER SHAM BIN ABDUL MUKTI',
        day,
        18,
        48,
        outDay,
        7,
        2,
      );
      punch(4, 'OMAR BIN ISMAIL', day, 18, 51, outDay, 7, 4);
    }
  }
  data['attendance'] = attendance;

  final scans = <Map<String, dynamic>>[];
  for (var day = 10; day <= 30; day++) {
    for (var cp = 1; cp <= 4; cp++) {
      for (var slot = 0; slot < 12; slot++) {
        scans.add({
          'checkpoint_id': cp,
          'checkpoint_name': 'CP$cp',
          'checkpoint_position': cp,
          'scanned_at': _utcIso(2025, 11, day, slot * 2, (cp * 5 + day) % 55),
        });
      }
    }
  }
  data['scans'] = scans;

  final dir = Directory('build/pkk-reference');
  dir.createSync(recursive: true);
  File('${dir.path}/PKK_2_REFERENCE.pdf').writeAsBytesSync(
    await PkkPdfGenerator.generatePkk2(data: data, month: 11, year: 2025),
  );
  File('${dir.path}/PKK_3_REFERENCE.pdf').writeAsBytesSync(
    await PkkPdfGenerator.generatePkk3(data: data, month: 11, year: 2025),
  );
  File('${dir.path}/PKK_4_REFERENCE.pdf').writeAsBytesSync(
    await PkkPdfGenerator.generatePkk4(data: data, month: 11, year: 2025),
  );
}

String _utcIso(int year, int month, int day, int hour, int minute) {
  final local = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
  ).subtract(const Duration(hours: 8));
  return local.toIso8601String();
}
