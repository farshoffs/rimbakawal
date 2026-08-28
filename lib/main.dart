import 'package:flutter/material.dart';

import 'core/nfc/mock_nfc_service.dart';
import 'core/nfc/real_nfc_service.dart';
import 'features/auth/login_screen.dart';

const useMockNfc = bool.fromEnvironment(
  'USE_MOCK_NFC',
  defaultValue: false,
);

const rimbaRed = Color(0xFFC0392B);
const rimbaBlue = Color(0xFF4834D4);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RimbaKawalApp());
}

class RimbaKawalApp extends StatelessWidget {
  const RimbaKawalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: rimbaBlue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: rimbaRed,
      onPrimary: Colors.white,
      secondary: rimbaBlue,
      onSecondary: Colors.white,
      surface: const Color(0xFF15151F),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RimbaKawal',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF0B0B12),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0B12),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF171722),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF11111A),
          labelStyle: const TextStyle(color: Color(0xFFCBCAD8)),
          hintStyle: const TextStyle(color: Color(0xFF777687)),
          prefixIconColor: const Color(0xFFAAA8B8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF343340)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF343340)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: rimbaBlue, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: rimbaRed,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      home: LoginScreen(
        nfcService: useMockNfc ? MockNfcService() : RealNfcService(),
        mockMode: useMockNfc,
      ),
    );
  }
}
