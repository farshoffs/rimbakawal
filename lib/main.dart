import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/api/api_service.dart';
import 'core/api/app_user.dart';
import 'core/nfc/mock_nfc_service.dart';
import 'core/nfc/nfc_service.dart';
import 'core/nfc/real_nfc_service.dart';
import 'core/notifications/notification_alert_gate.dart';
import 'core/notifications/notification_service.dart';
import 'core/offline/offline_store.dart';
import 'core/offline/offline_sync_service.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/sos/sos_alert_gate.dart';

const useMockNfc = bool.fromEnvironment(
  'USE_MOCK_NFC',
  defaultValue: false,
);

const rimbaRed = Color(0xFFC0392B);
const rimbaBlue = Color(0xFF4834D4);
const rimbaInk = Color(0xFF080910);
const rimbaSurface = Color(0xFF12141E);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OfflineStore.instance.init();
  await ApiService.instance.init();
  await NotificationService.instance.init();
  await OfflineSyncService.instance.start();
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
      secondary: const Color(0xFF6C5CE7),
      onSecondary: Colors.white,
      surface: rimbaSurface,
      surfaceContainerHighest: const Color(0xFF1C2030),
      error: const Color(0xFFFF5D66),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RimbaKawal',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: rimbaInk,
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        appBarTheme: const AppBarTheme(
          backgroundColor: rimbaInk,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: rimbaSurface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0E1018),
          labelStyle: const TextStyle(color: Color(0xFFC8CBD8)),
          hintStyle: const TextStyle(color: Color(0xFF737788)),
          prefixIconColor: const Color(0xFFAAAFC0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF303444)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF303444)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: rimbaBlue, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: rimbaRed,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        chipTheme: ChipThemeData(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF222636),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final ApiService _api = ApiService.instance;
  late final NfcService _nfcService;
  late Future<AppUser?> _session;

  @override
  void initState() {
    super.initState();
    _nfcService = kIsWeb
        ? (useMockNfc ? MockNfcService() : RealNfcService())
        : RealNfcService();
    _session = _api.getSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(nfcService: _nfcService, mockMode: useMockNfc);
        }

        return NotificationAlertGate(
          child: SosAlertGate(
            user: user,
            child: DashboardScreen(
              user: user,
              api: _api,
              nfcService: _nfcService,
              mockMode: useMockNfc,
            ),
          ),
        );
      },
    );
  }
}
