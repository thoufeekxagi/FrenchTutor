import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../services/auth_service.dart';
import '../../v3/ui/v3_ui.dart';

class SpeakAuthScreen extends StatefulWidget {
  const SpeakAuthScreen({super.key, this.initialSignUp = true});

  final bool initialSignUp;

  @override
  State<SpeakAuthScreen> createState() => _SpeakAuthScreenState();
}

class _SpeakAuthScreenState extends State<SpeakAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  late var _signUp = widget.initialSignUp;
  var _loading = false;
  var _awaitingEmailConfirmation = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
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
      switch (result.outcome) {
        case AuthOutcome.success:
        case AuthOutcome.cancelled:
          _awaitingEmailConfirmation = false;
          _message = null;
          break;
        case AuthOutcome.needsEmailConfirmation:
          _awaitingEmailConfirmation = true;
          _message =
              'Check your inbox for the confirmation link. Open it on this device to finish signing in.';
          break;
        case AuthOutcome.accountMayAlreadyExist:
          _awaitingEmailConfirmation = false;
          _message = null;
          break;
        case AuthOutcome.failure:
          _awaitingEmailConfirmation = false;
          _message = result.message;
          break;
      }
    });
    if (result.outcome == AuthOutcome.accountMayAlreadyExist) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black,
            content: Text(
              AuthResult.accountMayAlreadyExistMessage,
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
    }
  }

  Future<void> _resendConfirmation() async {
    if (_loading) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Enter your email address first.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await AuthService.shared.resendSignupConfirmation(email);
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Keep the recovery action available on transient resend errors so the
      // learner can retry without switching screens or re-entering a password.
      _awaitingEmailConfirmation = true;
      _message = switch (result.outcome) {
        AuthOutcome.success =>
          'If this account still needs confirmation, a fresh link has been sent. Check your inbox and spam folder.',
        AuthOutcome.cancelled => null,
        AuthOutcome.needsEmailConfirmation =>
          'Check your inbox for the confirmation link.',
        AuthOutcome.accountMayAlreadyExist =>
          AuthResult.accountMayAlreadyExistMessage,
        AuthOutcome.failure => result.message,
      };
    });
  }

  Future<void> _sendPasswordReset() async {
    if (_loading) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Enter your email address first.');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await AuthService.shared.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = switch (result.outcome) {
        AuthOutcome.success =>
          'If this email is registered, a reset link has been sent. Open it on this device to choose a new password.',
        AuthOutcome.cancelled => null,
        AuthOutcome.needsEmailConfirmation =>
          'Check your inbox for the confirmation link first.',
        AuthOutcome.accountMayAlreadyExist =>
          AuthResult.accountMayAlreadyExistMessage,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Apple buttons use the official high-contrast pairing for the active
    // appearance. Google keeps its white surface in both themes, but always
    // uses Google's dark text instead of inheriting the dark app text color.
    final appleBackground = isDark ? Colors.white : Colors.black;
    final appleForeground = isDark ? Colors.black : Colors.white;
    const googleBackground = Colors.white;
    const googleForeground = DesignTokens.googleButtonForeground;
    const googleBorder = DesignTokens.googleButtonBorder;

    // Same look as onboarding: the mark, one heading, rows, one main button.
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: V3Width(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DesignTokens.hairline),
                    ),
                    child: Image.asset(
                      'assets/images/parlesprint_app_icon.png',
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'ParleSprint',
                    style: V3Type.strong(15, DesignTokens.primary),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Text(
                _signUp ? 'Save your progress.' : 'Welcome back.',
                style: V3Type.title(36),
              ),
              const SizedBox(height: 26),
              _providerButton(
                Icons.apple_rounded,
                'Continue with Apple',
                appleBackground,
                appleForeground,
                () => _run(AuthService.shared.signInWithApple),
                key: const ValueKey('auth.apple'),
              ),
              const SizedBox(height: 10),
              _providerButton(
                Icons.g_mobiledata_rounded,
                'Continue with Google',
                googleBackground,
                googleForeground,
                () => _run(AuthService.shared.signInWithGoogle),
                outlined: true,
                borderColor: googleBorder,
                key: const ValueKey('auth.google'),
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
                  Expanded(child: Divider(color: DesignTokens.hairline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or use email', style: V3Type.body(13)),
                  ),
                  Expanded(child: Divider(color: DesignTokens.hairline)),
                ],
              ),
              const SizedBox(height: 18),
              _field(
                _email,
                _emailFocusNode,
                'Email address',
                CupertinoIcons.mail,
                key: const ValueKey('auth.email'),
              ),
              const SizedBox(height: 10),
              _field(
                _password,
                _passwordFocusNode,
                'Password',
                CupertinoIcons.lock,
                obscure: true,
                key: const ValueKey('auth.password'),
              ),
              if (!_signUp)
                Align(
                  alignment: Alignment.centerRight,
                  child: V3Pressable(
                    key: const ValueKey('auth.forgot'),
                    label: 'Forgot password?',
                    onTap: _loading ? null : _sendPasswordReset,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Forgot password?',
                        style: V3Type.strong(14, DesignTokens.primary),
                      ),
                    ),
                  ),
                ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(_message!, style: V3Type.body(14, DesignTokens.ink)),
              ],
              if (_awaitingEmailConfirmation)
                V3TextAction(
                  key: const ValueKey('auth.resend'),
                  label: _loading ? 'Sending…' : 'Resend confirmation email',
                  onTap: _loading ? null : _resendConfirmation,
                ),
              const SizedBox(height: 18),
              V3Button(
                key: const ValueKey('auth.submit'),
                label: _signUp ? 'Create account' : 'Sign in',
                loading: _loading,
                onTap: _submitEmail,
              ),
              V3TextAction(
                key: const ValueKey('auth.toggle'),
                label: _signUp
                    ? 'Already have an account? Sign in'
                    : 'New to ParleSprint? Create an account',
                onTap: () => setState(() {
                  _signUp = !_signUp;
                  _awaitingEmailConfirmation = false;
                  _message = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'By continuing, you agree to our Terms and Privacy Policy.',
                style: V3Type.body(12),
              ),
            ],
          ),
        ),
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
    Color? borderColor,
    Widget? leading,
    Key? key,
  }) {
    return V3Pressable(
      key: key,
      label: label,
      onTap: _loading ? null : onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: outlined
              ? Border.all(color: borderColor ?? DesignTokens.hairline)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading ?? Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 10),
            Text(label, style: V3Type.strong(16, foreground)),
          ],
        ),
      ),
    );
  }

  /// A row, like every other choice in the app: white, rounded, hairline.
  Widget _field(
    TextEditingController controller,
    FocusNode focusNode,
    String hint,
    IconData icon, {
    bool obscure = false,
    Key? key,
  }) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
            border: Border.all(
              color: focused ? DesignTokens.primary : DesignTokens.hairline,
              width: focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: DesignTokens.inkSoft, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: key,
                  controller: controller,
                  focusNode: focusNode,
                  obscureText: obscure,
                  autocorrect: false,
                  keyboardType: obscure
                      ? TextInputType.visiblePassword
                      : TextInputType.emailAddress,
                  cursorColor: DesignTokens.primary,
                  style: V3Type.strong(18, DesignTokens.ink),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: V3Type.body(18, DesignTokens.inkSoft),
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
