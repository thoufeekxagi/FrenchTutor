import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        ValueNotifier,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:google_sign_in/google_sign_in.dart' as google;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_keys.dart';

/// What happened after an auth attempt — deliberately distinct from a plain
/// success/failure boolean so the UI can tell "the user tapped Cancel on the
/// native sheet" (say nothing) apart from "something actually went wrong"
/// (show an error), and apart from "it worked, but check your email" (email
/// sign-up with confirmation enabled never returns an active session).
enum AuthOutcome {
  success,
  cancelled,
  needsEmailConfirmation,
  accountMayAlreadyExist,
  failure,
}

class AuthResult {
  static const accountMayAlreadyExistMessage =
      'This email may already have an account. If you signed up with Google, choose Continue with Google. Otherwise, switch to Sign in.';

  const AuthResult._(this.outcome, {this.message});

  final AuthOutcome outcome;
  final String? message;

  static const cancelled = AuthResult._(AuthOutcome.cancelled);
  static const success = AuthResult._(AuthOutcome.success);
  static const needsEmailConfirmation = AuthResult._(
    AuthOutcome.needsEmailConfirmation,
  );
  static const accountMayAlreadyExist = AuthResult._(
    AuthOutcome.accountMayAlreadyExist,
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
  static const _signedOutMarkerKey = 'auth_gate_signed_out_v1';

  /// iOS custom URL callback used by Supabase's email verification flow.
  /// This scheme is also registered in Runner/Info.plist and must be
  /// allow-listed in Supabase Auth > URL Configuration.
  static const iosEmailAuthCallbackUrl =
      'com.thoufeekx.frenchtutor://auth-callback';

  /// Resolves to an exact URL already registered in Supabase Auth. Web uses
  /// the current origin; iOS uses the app callback; Android stays on the
  /// configured Site URL until its app-link callback is registered.
  @visibleForTesting
  static String? emailRedirectToForPlatform({
    required bool isWeb,
    required TargetPlatform platform,
    Uri? webUri,
  }) {
    if (isWeb) return webUri?.origin;
    if (platform == TargetPlatform.iOS) return iosEmailAuthCallbackUrl;
    return null;
  }

  // Supabase emits SIGNED_OUT as soon as its local session is removed, but
  // this signal also gives the app shell a synchronous fallback if a stream
  // delivery is delayed by a platform lifecycle transition.
  final ValueNotifier<int> _localAuthRevision = ValueNotifier<int>(0);

  SupabaseClient get _client => Supabase.instance.client;

  /// The confirmation callback is deliberately platform-specific. iOS is
  /// registered in this change; other native platforms keep their existing
  /// Site URL behavior until their callback schemes are configured too.
  String? get _emailRedirectTo => emailRedirectToForPlatform(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    webUri: Uri.base,
  );

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

  /// The identity details safe to show in Profile settings. Passwords are
  /// intentionally never exposed by Supabase or by this app.
  String? get signedInEmail => currentSession?.user.email;

  /// The address Supabase knows for the account. Apple may intentionally
  /// provide a private-relay address when the learner chooses Hide My Email;
  /// the real Apple address is never available to the app in that case.
  String? get signedInEmailLabel {
    final email = signedInEmail;
    if (email == null || email.isEmpty) return null;
    if (email.toLowerCase().endsWith('@privaterelay.appleid.com')) {
      return 'Apple private relay email';
    }
    return email;
  }

  String get signedInDisplayName {
    final user = currentSession?.user;
    final metadata = user?.userMetadata;
    final name =
        metadata?['full_name'] ??
        metadata?['name'] ??
        metadata?['display_name'] ??
        metadata?['user_name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    final email = signedInEmail;
    if (email == null || !email.contains('@')) return 'French Tutor learner';
    if (email.toLowerCase().endsWith('@privaterelay.appleid.com')) {
      return 'French learner';
    }
    return email.split('@').first;
  }

  String get signedInProvider {
    final user = currentSession?.user;
    final raw =
        user?.appMetadata['provider'] ?? user?.userMetadata?['provider'];
    switch (raw?.toString().toLowerCase()) {
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      case 'email':
      case 'password':
        return 'Email and password';
      default:
        return raw is String && raw.trim().isNotEmpty
            ? raw.trim()
            : 'Account sign-in';
    }
  }

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  ValueListenable<int> get localAuthRevision => _localAuthRevision;

  Future<bool> wasExplicitlySignedOut() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_signedOutMarkerKey) == true;
  }

  Future<void> rememberSignedOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_signedOutMarkerKey, true);
  }

  Future<void> clearRememberedSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_signedOutMarkerKey);
  }

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
        email: email.trim(),
        password: password,
        emailRedirectTo: _emailRedirectTo,
      );
      return classifySignUpResponse(
        user: response.user,
        session: response.session,
      );
    } on AuthException catch (e) {
      if (_requiresEmailConfirmation(e)) {
        return AuthResult.needsEmailConfirmation;
      }
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Sign-up failed: $e');
    }
  }

  /// Supabase intentionally returns a successful-looking user with no
  /// identities when an email already belongs to another account. It sends no
  /// confirmation email in that case to prevent account enumeration. Detect
  /// that response so the UI can guide the learner to their original sign-in
  /// method instead of telling them to check an inbox that will stay empty.
  @visibleForTesting
  static AuthResult classifySignUpResponse({
    required User? user,
    required Session? session,
  }) {
    if (user != null && user.identities != null && user.identities!.isEmpty) {
      return AuthResult.accountMayAlreadyExist;
    }
    if (session == null) return AuthResult.needsEmailConfirmation;
    return AuthResult.success;
  }

  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return AuthResult.success;
    } on AuthException catch (e) {
      if (_requiresEmailConfirmation(e)) {
        return AuthResult.needsEmailConfirmation;
      }
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Sign-in failed: $e');
    }
  }

  /// Sends another Supabase-generated signup confirmation link. Supabase
  /// remains the source of the one-time token; the redirect only tells the
  /// verified link where to return after it has been consumed.
  Future<AuthResult> resendSignupConfirmation(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: _emailRedirectTo,
      );
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Couldn\'t resend the confirmation email: $e');
    }
  }

  bool _requiresEmailConfirmation(AuthException error) {
    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();
    return code == 'email_not_confirmed' ||
        message.contains('email not confirmed') ||
        message.contains('email_not_confirmed');
  }

  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _emailRedirectTo,
      );
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Couldn\'t send the reset email: $e');
    }
  }

  /// Changes a password only after Supabase has returned a verified recovery
  /// session to this device. It never attempts an admin or unauthenticated
  /// password update.
  Future<AuthResult> updatePasswordAfterRecovery(String password) async {
    try {
      if (_client.auth.currentSession == null) {
        return AuthResult.failure(
          'This reset link is no longer active. Request a fresh one and try again.',
        );
      }
      await _client.auth.updateUser(UserAttributes(password: password));
      return AuthResult.success;
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Couldn\'t update the password: $e');
    }
  }

  Future<void> signOut() async {
    Future<void>? request;
    try {
      // Calling signOut starts the local session removal synchronously inside
      // gotrue, before its optional server-side revocation request. Notify
      // the app shell now so the user never waits on that network request to
      // reach the account screen.
      request = _client.auth.signOut();
    } catch (_) {
      // Keep the local UI transition best-effort even if the SDK throws while
      // starting the request.
    }
    _localAuthRevision.value++;
    try {
      await request;
    } catch (_) {
      // Local sign-out already happened. A failed remote revocation must not
      // strand the user in the authenticated shell.
    }
    try {
      await rememberSignedOut();
    } catch (_) {
      // The in-memory auth transition is already complete; persistence is
      // only a convenience for the next app launch.
    }
  }

  /// Removes the local session and notifies AuthGate without waiting for
  /// Supabase's optional server-side session revocation request. This is
  /// required after account deletion: the server has already removed the
  /// Auth user, so waiting for /logout can only produce a harmless 403 and
  /// must never hold the user on a deletion spinner.
  Future<void> signOutLocallyImmediately() async {
    try {
      final request = _client.auth.signOut(scope: SignOutScope.local);
      _localAuthRevision.value++;
      unawaited(request.catchError((_) {}));
    } catch (_) {
      _localAuthRevision.value++;
    }
    try {
      await rememberSignedOut();
    } catch (_) {
      // The in-memory session is already gone; persistence is best effort.
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
  String? _functionErrorMessage(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == '{}') return null;
      try {
        final decoded = jsonDecode(text);
        final nested = _functionErrorMessage(decoded);
        if (nested != null) return nested;
      } catch (_) {
        // The response is plain text, which is already suitable to show.
      }
      return text;
    }
    if (value is Map) {
      for (final key in const ['error', 'message', 'details', 'msg']) {
        final message = _functionErrorMessage(value[key]);
        if (message != null) return message;
      }
    }
    return null;
  }

  Future<AuthResult> deleteAccount() async {
    try {
      final response = await _client.functions
          .invoke('delete-account')
          .timeout(const Duration(seconds: 60));
      if (response.status != 200) {
        final error = _functionErrorMessage(response.data);
        return AuthResult.failure(
          error ?? 'Account deletion failed (${response.status}).',
        );
      }
      return AuthResult.success;
    } on FunctionException catch (e) {
      return AuthResult.failure(
        _functionErrorMessage(e.details) ??
            'Account deletion failed: ${e.reasonPhrase}',
      );
    } on TimeoutException {
      return AuthResult.failure(
        'Account deletion is taking too long. Please check your connection '
        'and try again.',
      );
    } catch (e) {
      return AuthResult.failure('Account deletion failed: $e');
    }
  }
}
