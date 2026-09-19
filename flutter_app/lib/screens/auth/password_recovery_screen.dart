import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../services/auth_service.dart';
import '../speak/speak_ui.dart';

/// Shown only after Supabase has exchanged a recovery link and emitted its
/// passwordRecovery auth event. The new password is submitted using that
/// short-lived authenticated recovery session.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    required this.onContinue,
    required this.onCancel,
  });

  final VoidCallback onContinue;
  final Future<void> Function() onCancel;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  bool _saved = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (_loading || _saved) return;
    final password = _password.text;
    if (password.length < 8) {
      setState(() {
        _isError = true;
        _message = 'Use at least 8 characters for your new password.';
      });
      return;
    }
    if (password != _confirmPassword.text) {
      setState(() {
        _isError = true;
        _message = 'Those passwords do not match.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
      _isError = false;
    });
    final result = await AuthService.shared.updatePasswordAfterRecovery(
      password,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _saved = result.outcome == AuthOutcome.success;
      _isError = result.outcome != AuthOutcome.success;
      _message = _saved
          ? 'Your password has been updated. You are signed in.'
          : result.message ?? 'Could not update your password. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 32),
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: SpeakColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: Colors.black,
                size: 27,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _saved ? 'Password updated.' : 'Choose a new password.',
            textAlign: TextAlign.center,
            style: DesignTokens.display(28),
          ),
          const SizedBox(height: 10),
          Text(
            _saved
                ? 'Your ParleSprint account is ready.'
                : 'Set a new password for your ParleSprint account.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(
              14,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
          ),
          if (!_saved) ...[
            const SizedBox(height: 28),
            _passwordField(_password, 'New password'),
            const SizedBox(height: 12),
            _passwordField(_confirmPassword, 'Confirm new password'),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: DesignTokens.body(12).copyWith(
                color: _isError ? DesignTokens.danger : SpeakColors.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 22),
          SpeakPrimaryButton(
            label: _loading
                ? 'Updating…'
                : _saved
                ? 'Continue to ParleSprint'
                : 'Save new password',
            icon: _saved ? Icons.arrow_forward_rounded : Icons.check_rounded,
            onTap: _loading
                ? () {}
                : _saved
                ? widget.onContinue
                : _savePassword,
          ),
          if (!_saved) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: _loading ? null : widget.onCancel,
              child: const Text('Back to sign in'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _passwordField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      cursorColor: DesignTokens.primaryReadable,
      style: DesignTokens.body(14).copyWith(color: Colors.black87),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        hintText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
