import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../services/auth_service.dart';
import '../speak/speak_ui.dart';

class SpeakAuthScreen extends StatefulWidget {
  const SpeakAuthScreen({super.key});

  @override
  State<SpeakAuthScreen> createState() => _SpeakAuthScreenState();
}

class _SpeakAuthScreenState extends State<SpeakAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _signUp = true;
  var _loading = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthResult> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = switch (result.outcome) {
        AuthOutcome.success => null,
        AuthOutcome.cancelled => null,
        AuthOutcome.needsEmailConfirmation =>
          'Check your email to confirm your account.',
        AuthOutcome.failure => result.message,
      };
    });
  }

  void _submitEmail() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Enter your email and password.');
      return;
    }
    _run(
      () => _signUp
          ? AuthService.shared.signUpWithEmail(email: email, password: password)
          : AuthService.shared.signInWithEmail(
              email: email,
              password: password,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: SpeakColors.blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _signUp ? 'Save your plan\nand keep speaking.' : 'Welcome back.',
            textAlign: TextAlign.center,
            style: DesignTokens.display(29),
          ),
          const SizedBox(height: 9),
          Text(
            _signUp
                ? 'Create an account so your course, roleplays and progress stay with you.'
                : 'Pick up exactly where you left off.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              14,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 28),
          _providerButton(
            Icons.apple_rounded,
            'Continue with Apple',
            Colors.black,
            Colors.white,
            () => _run(AuthService.shared.signInWithApple),
          ),
          const SizedBox(height: 10),
          _providerButton(
            Icons.g_mobiledata_rounded,
            'Continue with Google',
            Colors.white,
            SpeakColors.navy,
            () => _run(AuthService.shared.signInWithGoogle),
            outlined: true,
            leading: Image.asset(
              'assets/images/google_logo.png',
              width: 22,
              height: 22,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Divider(color: SpeakColors.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or use email',
                  style: DesignTokens.body(
                    11,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ),
              const Expanded(child: Divider(color: SpeakColors.line)),
            ],
          ),
          const SizedBox(height: 18),
          _field(_email, 'Email address', Icons.mail_outline_rounded),
          const SizedBox(height: 10),
          _field(
            _password,
            'Password',
            Icons.lock_outline_rounded,
            obscure: true,
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: DesignTokens.body(12).copyWith(color: SpeakColors.inkSoft),
            ),
          ],
          const SizedBox(height: 16),
          SpeakPrimaryButton(
            label: _loading
                ? 'Working…'
                : _signUp
                ? 'Create account'
                : 'Sign in',
            icon: Icons.arrow_forward_rounded,
            onTap: _loading ? () {} : _submitEmail,
          ),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: () => setState(() {
                _signUp = !_signUp;
                _message = null;
              }),
              child: Text(
                _signUp
                    ? 'Already have an account? Sign in'
                    : 'New to ParleSprint? Create an account',
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w700,
                ).copyWith(color: SpeakColors.blue),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'By continuing, you agree to our Terms and Privacy Policy.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(10.5).copyWith(color: SpeakColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _providerButton(
    IconData icon,
    String label,
    Color background,
    Color foreground,
    VoidCallback onTap, {
    bool outlined = false,
    Widget? leading,
  }) {
    return GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: outlined ? Border.all(color: SpeakColors.navy) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading ?? Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 9),
            Text(
              label,
              style: DesignTokens.body(
                14,
                weight: FontWeight.w700,
              ).copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: obscure
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: SpeakColors.inkSoft, size: 20),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SpeakColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SpeakColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SpeakColors.blue, width: 2),
        ),
      ),
    );
  }
}
