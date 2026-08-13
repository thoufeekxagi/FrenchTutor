import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart' as google;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_keys.dart';

/// What happened after an auth attempt — deliberately distinct from a plain
/// success/failure boolean so the UI can tell "the user tapped Cancel on the
/// native sheet" (say nothing) apart from "something actually went wrong"
/// (show an error), and apart from "it worked, but check your email" (email
/// sign-up with confirmation enabled never returns an active session).
enum AuthOutcome { success, cancelled, needsEmailConfirmation, failure }

class AuthResult {
  const AuthResult._(this.outcome, {this.message});

  final AuthOutcome outcome;
  final String? message;

  static const cancelled = AuthResult._(AuthOutcome.cancelled);
  static const success = AuthResult._(AuthOutcome.success);
  static const needsEmailConfirmation = AuthResult._(
    AuthOutcome.needsEmailConfirmation,
  );
  static AuthResult failure(String message) =>
      AuthResult._(AuthOutcome.failure, message: message);
}

/// Every native-auth entry point the app offers, wrapped so the UI layer
/// never has to know about Google/Apple/Supabase exception shapes directly —
/// it only ever sees an [AuthResult]. No path here can throw past this class;
/// every external SDK call is caught, because a user cancelling a sign-in
/// sheet is routine, not exceptional, and must never crash the screen.
class AuthService {
  AuthService._();

  static final AuthService shared = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// True once real Google OAuth client IDs have been configured (Google
  /// Cloud Console — see BUILD_FLUTTER_TO_IPHONE.md). Until then the Google
  /// button in the UI stays visible but returns a friendly explanation
  /// instead of attempting a sign-in that would fail with an obscure native
  /// error.
  /// On web only the web client ID is relevant — the iOS client ID is for the
  /// native SDK, which is not used there (see [signInWithGoogle]).
  bool get isGoogleConfigured => kIsWeb
      ? ApiKeys.googleWebClientId.isNotEmpty
      : ApiKeys.googleIosClientId.isNotEmpty &&
            ApiKeys.googleWebClientId.isNotEmpty;

  /// Apple sign-in on web needs an Apple Developer **Service ID** plus a
  /// redirect URL, not just the native bundle ID. Until that's configured,
  /// hide the button on web.
  bool get isAppleAvailable => !kIsWeb;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  // ---------------------------------------------------------------------------
  // Google — native account picker, signInWithIdToken (no browser, ever).
  // ---------------------------------------------------------------------------

  Future<AuthResult> signInWithGoogle() async {
    if (!isGoogleConfigured) {
      return AuthResult.failure(
        'Google sign-in isn\'t set up yet, use Apple or email for now.',
      );
    }
    // The one platform branch in this file, and it lives here deliberately:
    // AuthService IS the leaf seam for "trigger a sign-in", so the split
    // belongs at this boundary rather than being pushed up into any screen.
    //
    // Native uses the Google SDK's account picker + signInWithIdToken, so no
    // browser ever opens. That approach has no web equivalent: on web the
    // google_sign_in plugin renders its own button and cannot be driven from
    // an arbitrary onTap. Supabase's OAuth redirect is the supported web flow
    // and needs no extra client-side wiring; it returns here with a session,
    // which onAuthStateChange delivers to AuthGate exactly like any other
    // sign-in. Requires the site URL / redirect URL to be allow-listed in the
    // Supabase dashboard (see docs/web_migration/03_phase3_auth_and_payments.md).
    if (kIsWeb) {
      try {
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
        );
        // The page navigates away; the session arrives via onAuthStateChange
        // after the redirect back, so there is nothing to report synchronously.
        return AuthResult.success;
      } on AuthException catch (e) {
        return AuthResult.failure(e.message);
      } catch (e) {
        return AuthResult.failure('Google sign-in failed: $e');
      }
    }
    try {
      final googleSignIn = google.GoogleSignIn(
        clientId: ApiKeys.googleIosClientId,
        serverClientId: ApiKeys.googleWebClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the native account picker — routine, not an error.
        return AuthResult.cancelled;
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        return AuthResult.failure(
          'Google didn\'t return the expected sign-in details. Please try again.',
        );
      }
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Google sign-in failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Apple — native system sheet, signInWithIdToken (no browser, ever).
  // ---------------------------------------------------------------------------

  Future<AuthResult> signInWithApple() async {
    try {
      final rawNonce = _client.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        return AuthResult.failure(
          'Apple didn\'t return the expected sign-in details. Please try again.',
        );
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      return AuthResult.success;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AuthResult.cancelled;
      }
      return AuthResult.failure('Apple sign-in failed: ${e.message}');
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Apple sign-in failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Email / password.
  // ---------------------------------------------------------------------------

  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      // With email confirmation required (the project default), signUp
      // succeeds but returns no active session until the user clicks the
      // link in their inbox — that is success, just not an active login yet.
      if (response.session == null) {
        return AuthResult.needsEmailConfirmation;
      }
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Sign-up failed: $e');
    }
  }

  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Sign-in failed: $e');
    }
  }

  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Couldn\'t send the reset email: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Best-effort: even if the network call fails, the local session is
      // cleared by supabase_flutter, so the user still ends up signed out
      // client-side, which is what matters for the UI.
    }
  }

  // ---------------------------------------------------------------------------
  // Account deletion (Apple Guideline 5.1.1(v) — must be reachable in-app).
  // ---------------------------------------------------------------------------

  /// Permanently deletes the signed-in user's Supabase account via the
  /// `delete-account` edge function. Unlike [signOut], failure here must be
  /// surfaced to the caller — the UI should not wipe local data or sign the
  /// user out unless this actually succeeds server-side, or a deleted-locally
  /// but still-live-remotely account could be left behind.
  Future<AuthResult> deleteAccount() async {
    try {
      final response = await _client.functions.invoke('delete-account');
      if (response.status != 200) {
        final error = response.data is Map ? response.data['error'] : null;
        return AuthResult.failure(
          error?.toString() ?? 'Account deletion failed (${response.status}).',
        );
      }
      return AuthResult.success;
    } on FunctionException catch (e) {
      return AuthResult.failure(
        e.details?.toString() ?? 'Account deletion failed: ${e.reasonPhrase}',
      );
    } catch (e) {
      return AuthResult.failure('Account deletion failed: $e');
    }
  }
}
