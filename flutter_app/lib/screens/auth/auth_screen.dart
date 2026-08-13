import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/auth_form.dart';
import '../../widgets/web/web_auth_layout.dart';

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
          // The app-level auth-state listener handles navigation from here.
          break;
        case AuthOutcome.cancelled:
          // The user backed out of a native sheet. Say nothing.
          break;
        case AuthOutcome.needsEmailConfirmation:
          _infoMessage =
              'Check your email to confirm your account, then sign in.';
          break;
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
          : AuthService.shared.signInWithEmail(
              email: email,
              password: password,
            ),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _clearMessages();
        _errorMessage =
            'Enter your email above first, then tap "Forgot password?".';
      });
      return;
    }
    await _run(() => AuthService.shared.sendPasswordReset(email));
    if (!mounted || _errorMessage != null) return;
    setState(
      () => _infoMessage = 'Password reset email sent, check your inbox.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= DesignTokens.breakpointExpanded) {
          return WebAuthLayout(child: _formContent(onDark: false));
        }
        return Scaffold(
          backgroundColor: DesignTokens.canvas,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: WebAuthFrame(child: _formContent(onDark: false)),
            ),
          ),
        );
      },
    );
  }

  Widget _formContent({required bool onDark}) {
    return AuthForm(
      emailController: _emailController,
      passwordController: _passwordController,
      isSignUp: _isSignUp,
      loading: _loading,
      errorMessage: _errorMessage,
      infoMessage: _infoMessage,
      appleAvailable: AuthService.shared.isAppleAvailable,
      onApple: _submitApple,
      onGoogle: _submitGoogle,
      onSubmit: _submitEmail,
      onForgotPassword: _forgotPassword,
      onModeChanged: (value) {
        PSHaptics.selection();
        setState(() {
          _isSignUp = value;
          _clearMessages();
        });
      },
      onDark: onDark,
    );
  }
}
