import 'package:flutter/material.dart';

import 'core/nfc/mock_nfc_service.dart';
import 'core/nfc/real_nfc_service.dart';
import 'features/patrol/patrol_screen.dart';

const useMockNfc = bool.fromEnvironment(
  'USE_MOCK_NFC',
  defaultValue: false,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PatrolApp());
}

class PatrolApp extends StatelessWidget {
  const PatrolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RimbaKawal Patrol',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: PatrolScreen(
        nfcService: useMockNfc ? MockNfcService() : RealNfcService(),
        mockMode: useMockNfc,
      ),
    );
  }
}
