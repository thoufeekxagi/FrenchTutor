import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_primary_button.dart';

/// The one-and-only entry screen: Apple, Google, and email/password, no
/// exceptions, no browser tabs — every path here resolves inside the app or
/// shows a plain-language reason it didn't (never a silent dead end).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _loading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearMessages() {
    _errorMessage = null;
    _infoMessage = null;
  }

  Future<void> _run(Future<AuthResult> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _clearMessages();
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result.outcome) {
        case AuthOutcome.success:
          // The app-level auth-state listener handles navigation from here —
          // this screen simply stops showing a spinner and disappears once
          // the session stream fires.
          break;
        case AuthOutcome.cancelled:
          // The user backed out of a native sheet — say nothing, exactly as
          // if they'd never tapped the button.
          break;
        case AuthOutcome.needsEmailConfirmation:
          _infoMessage =
              'Check your email to confirm your account, then sign in.';
        case AuthOutcome.failure:
          _errorMessage = result.message;
      }
    });
  }

  void _submitApple() => _run(AuthService.shared.signInWithApple);
  void _submitGoogle() => _run(AuthService.shared.signInWithGoogle);

  void _submitEmail() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _clearMessages();
        _errorMessage = 'Enter your email and password.';
      });
      return;
    }
    _run(
      () => _isSignUp
          ? AuthService.shared.signUpWithEmail(email: email, password: password)
          : AuthService.shared.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _clearMessages();
        _errorMessage = 'Enter your email above first, then tap "Forgot password?".';
      });
      return;
    }
    await _run(() => AuthService.shared.sendPasswordReset(email));
    if (!mounted) return;
    if (_errorMessage == null) {
      setState(() => _infoMessage = 'Password reset email sent — check your inbox.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 40),
              _appleButton(),
              const SizedBox(height: 12),
              _googleButton(),
              const SizedBox(height: 24),
              _divider(),
              const SizedBox(height: 20),
              _modeToggle(),
              const SizedBox(height: 18),
              _emailField(),
              const SizedBox(height: 12),
              _passwordField(),
              if (!_isSignUp) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _loading ? null : _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: Passeport.body(
                        12.5,
                        weight: FontWeight.w600,
                      ).copyWith(color: Passeport.maroon),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_errorMessage != null) _messageBanner(_errorMessage!, isError: true),
              if (_infoMessage != null) _messageBanner(_infoMessage!, isError: false),
              if (_errorMessage != null || _infoMessage != null)
                const SizedBox(height: 12),
              PasseportPrimaryButton(
                label: _loading
                    ? 'Please wait…'
                    : (_isSignUp ? 'Create account' : 'Sign in'),
                onPressed: _loading ? null : _submitEmail,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PARLESPRINT',
          style: Passeport.body(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: Passeport.maroon, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        Text('Welcome', style: Passeport.display(30)),
        const SizedBox(height: 6),
        Text(
          'Sign in to save your progress and pick up right where you left off.',
          style: Passeport.body(14).copyWith(color: Passeport.slateDim, height: 1.4),
        ),
      ],
    );
  }

  Widget _appleButton() {
    return SizedBox(
      height: 52,
      child: SignInWithAppleButton(
        onPressed: _loading ? () {} : _submitApple,
        style: SignInWithAppleButtonStyle.black,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  /// No bundled Google logo asset (avoiding the risk of a hand-encoded,
  /// possibly-malformed vector) — a clean brand-blue "G" monogram in a
  /// bordered, Passeport-styled button reads as deliberate, not missing.
  Widget _googleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _loading ? null : _submitGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Passeport.surface,
          side: BorderSide(color: Passeport.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4285F4),
              ),
              child: const Text(
                'G',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Continue with Google',
              style: Passeport.body(15, weight: FontWeight.w600).copyWith(
                color: Passeport.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Passeport.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with email',
            style: Passeport.body(12).copyWith(color: Passeport.slateDim),
          ),
        ),
        Expanded(child: Divider(color: Passeport.hairline)),
      ],
    );
  }

  Widget _modeToggle() {
    return PSSegmented<bool>(
      segments: const [
        (value: false, label: 'Sign in'),
        (value: true, label: 'Create account'),
      ],
      selected: _isSignUp,
      onChanged: (value) {
        PSHaptics.selection();
        setState(() {
          _isSignUp = value;
          _clearMessages();
        });
      },
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: Passeport.body(13).copyWith(color: Passeport.slateDim),
      prefixIcon: Icon(icon, size: 19, color: Passeport.slateDim),
      filled: true,
      fillColor: Passeport.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Passeport.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Passeport.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Passeport.maroon, width: 1.5),
      ),
    );
  }

  Widget _emailField() {
    return TextField(
      controller: _emailController,
      enabled: !_loading,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      style: Passeport.body(14.5),
      decoration: _fieldDecoration('Email', CupertinoIcons.mail),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordController,
      enabled: !_loading,
      obscureText: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submitEmail(),
      style: Passeport.body(14.5),
      decoration: _fieldDecoration('Password', CupertinoIcons.lock),
    );
  }

  Widget _messageBanner(String text, {required bool isError}) {
    final color = isError ? Passeport.danger : Passeport.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: Passeport.body(12.5).copyWith(color: color, height: 1.35),
      ),
    );
  }
}
