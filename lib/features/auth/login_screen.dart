import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nfc/nfc_service.dart';
import '../patrol/patrol_screen.dart';

const _rimbaRed = Color(0xFFC0392B);
const _rimbaBlue = Color(0xFF4834D4);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.nfcService,
    required this.mockMode,
    super.key,
  });

  final NfcService nfcService;
  final bool mockMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identityCardController = TextEditingController();

  @override
  void dispose() {
    _identityCardController.dispose();
    super.dispose();
  }

  String? _validateIdentityCard(String? value) {
    final identityCard = value?.trim() ?? '';
    if (identityCard.isEmpty) {
      return 'Sila masukkan No. Kad Pengenalan.';
    }
    if (identityCard.length != 12) {
      return 'No. Kad Pengenalan mesti mengandungi 12 digit.';
    }
    return null;
  }

  void _continueToPatrol() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PatrolScreen(
          nfcService: widget.nfcService,
          mockMode: widget.mockMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(child: _TemporaryLogo()),
                        const SizedBox(height: 24),
                        Text(
                          'RimbaKawal',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sistem Rondaan Pintar',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: const Color(0xFFAAA8B8)),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xE6171722),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 32,
                                offset: Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Log masuk',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Masukkan No. Kad Pengenalan untuk meneruskan rondaan.',
                                style: TextStyle(
                                  color: Color(0xFFAAA8B8),
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _identityCardController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.username],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(12),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'No. Kad Pengenalan',
                                  hintText: 'Contoh: 001122031234',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: _validateIdentityCard,
                                onFieldSubmitted: (_) => _continueToPatrol(),
                              ),
                              const SizedBox(height: 20),
                              _GradientButton(
                                onPressed: _continueToPatrol,
                                label: 'Teruskan',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: Color(0xFF777687),
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Akses terhad kepada anggota yang berdaftar',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF777687),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemporaryLogo extends StatelessWidget {
  const _TemporaryLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_rimbaRed, _rimbaBlue],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x554834D4),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E16),
          borderRadius: BorderRadius.circular(27),
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.shield_outlined, color: Colors.white, size: 64),
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.forest, color: Color(0xFFB8AEFF), size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onPressed, required this.label});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_rimbaRed, _rimbaBlue]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x443E2BBE),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF080810), Color(0xFF111124), Color(0xFF120A0D)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -120,
            child: _Glow(color: _rimbaBlue.withValues(alpha: 0.20)),
          ),
          Positioned(
            bottom: -180,
            left: -140,
            child: _Glow(color: _rimbaRed.withValues(alpha: 0.18)),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      height: 360,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
