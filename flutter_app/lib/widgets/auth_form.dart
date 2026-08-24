import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/theme.dart';
import 'adaptive/adaptive.dart';
import 'passeport_primary_button.dart';

class AuthForm extends StatelessWidget {
  const AuthForm({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.isSignUp,
    required this.loading,
    required this.errorMessage,
    required this.infoMessage,
    required this.appleAvailable,
    required this.onApple,
    required this.onGoogle,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onModeChanged,
    required this.onDark,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isSignUp;
  final bool loading;
  final String? errorMessage;
  final String? infoMessage;
  final bool appleAvailable;
  final VoidCallback onApple;
  final VoidCallback onGoogle;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final ValueChanged<bool> onModeChanged;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 32),
        if (appleAvailable) ...[
          SizedBox(
            height: 52,
            child: SignInWithAppleButton(
              onPressed: loading ? () {} : onApple,
              style: SignInWithAppleButtonStyle.black,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: loading ? null : onGoogle,
            style: OutlinedButton.styleFrom(
              backgroundColor: Passeport.surface,
              side: BorderSide(color: Passeport.hairline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/google_logo.png',
                  width: 20,
                  height: 20,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Continue with Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Passeport.body(
                      15,
                      weight: FontWeight.w600,
                    ).copyWith(color: Passeport.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _divider(),
        const SizedBox(height: 20),
        PSSegmented<bool>(
          segments: const [
            (value: false, label: 'Sign in'),
            (value: true, label: 'Create account'),
          ],
          selected: isSignUp,
          onChanged: onModeChanged,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: emailController,
          enabled: !loading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          style: Passeport.body(14.5),
          decoration: _fieldDecoration('Email', CupertinoIcons.mail),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          enabled: !loading,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          style: Passeport.body(14.5),
          decoration: _fieldDecoration('Password', CupertinoIcons.lock),
        ),
        if (!isSignUp) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: loading ? null : onForgotPassword,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                foregroundColor: onDark ? Colors.white : Passeport.primary,
              ),
              child: const Text('Forgot password?'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (errorMessage != null) _messageBanner(errorMessage!, isError: true),
        if (infoMessage != null) _messageBanner(infoMessage!, isError: false),
        if (errorMessage != null || infoMessage != null)
          const SizedBox(height: 12),
        PasseportPrimaryButton(
          label: loading
              ? 'Please wait…'
              : (isSignUp ? 'Create account' : 'Sign in'),
          onPressed: loading ? null : onSubmit,
        ),
        const SizedBox(height: 18),
        Text(
          'By continuing, you agree to our Terms of Service and Privacy Policy.',
          textAlign: TextAlign.center,
          style: Passeport.body(11.5).copyWith(
            color: onDark
                ? Colors.white.withValues(alpha: 0.62)
                : Passeport.muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final headingColor = onDark ? Colors.white : Passeport.ink;
    final supportingColor = onDark
        ? Colors.white.withValues(alpha: 0.78)
        : Passeport.mutedDim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDark)
              Image.asset('assets/images/logo_mark.png', width: 18, height: 22)
            else
              Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Passeport.primarySoft,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                ),
                child: Image.asset('assets/images/logo_mark.png'),
              ),
            const SizedBox(width: 8),
            Text(
              'ParleSprint',
              style: Passeport.body(
                13,
                weight: FontWeight.w700,
              ).copyWith(color: headingColor, letterSpacing: 0.1),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          isSignUp ? 'Create your account' : 'Keep your progress',
          style: Passeport.display(30).copyWith(color: headingColor),
        ),
        const SizedBox(height: 8),
        Text(
          'Save your progress and pick up right where you left off.',
          style: Passeport.body(
            14,
          ).copyWith(color: supportingColor, height: 1.45),
        ),
      ],
    );
  }

  Widget _divider() {
    final color = onDark
        ? Colors.white.withValues(alpha: 0.3)
        : Passeport.hairline;
    final textColor = onDark
        ? Colors.white.withValues(alpha: 0.68)
        : Passeport.muted;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with email',
            style: Passeport.body(12).copyWith(color: textColor),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
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
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        borderSide: BorderSide(color: Passeport.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        borderSide: BorderSide(color: Passeport.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Passeport.maroon, width: 1.5),
      ),
    );
  }

  Widget _messageBanner(String text, {required bool isError}) {
    final color = isError ? Passeport.danger : Passeport.success;
    final textColor = onDark ? Colors.white : color;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: onDark
              ? color.withValues(alpha: 0.16)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? CupertinoIcons.exclamationmark_circle
                  : CupertinoIcons.checkmark_circle,
              size: 18,
              color: onDark ? Colors.white : color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Passeport.body(
                  12.5,
                ).copyWith(color: textColor, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
