import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/services/supabase_config.dart';
import '../models/user_profile.dart';

enum EmailStatus { notFound, foundButNotConfirmed, confirmed }

class AuthService {
  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? country,
    bool marketingConsent = false,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      // Step 1: Create the auth user, storing profile fields in metadata.
      // The profile row (id + email) is created by a Supabase trigger.
      // Profile fields are applied after email confirmation in applyMetadataToProfile().
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone_number': phoneNumber,
          'country': country,
          'marketing_consent': marketingConsent,
          'app_version_at_signup': appVersion,
        },
      );

      // Empty identities means this email is already registered — skip profile creation
      if (response.user?.identities != null &&
          response.user!.identities!.isEmpty) {
        return response;
      }

      return response;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<bool> trySignIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.session !=
          null; // Checks whether the session was authenticated, if so, the response is not null and thus completes as true
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> resendConfirmationEmail({required String email}) async {
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Checks whether an email has been confirmed by signing in with real credentials.
  /// Works regardless of Supabase's "Prevent email enumeration" setting.
  /// On confirmation, signs out immediately so the user can log in properly.
  Future<EmailStatus> checkEmailStatus(String email, String password) async {
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      // Confirmed — sign out to keep a clean state before the user logs in properly.
      try {
        await supabase.auth.signOut();
      } catch (_) {}
      return EmailStatus.confirmed;
    } on AuthException catch (e) {
      if (e.code == 'email_not_confirmed') {
        return EmailStatus.foundButNotConfirmed;
      }
      Sentry.captureMessage(
        'Unexpected error in checkEmailStatus: ${e.message} (code: ${e.code})',
      );
      return EmailStatus.notFound;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      return EmailStatus.notFound;
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  User? getCurrentUser() {
    return supabase.auth.currentUser;
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    try {
      final user = getCurrentUser();
      if (user == null) return null;

      final response =
          await supabase.from('profiles').select().eq('id', user.id).single();

      return UserProfile.fromJson(response);
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);

      return null;
    }
  }

  /// Applies profile fields stored in user metadata to the profiles table.
  /// Call this after the user confirms their email and signs in for the first time.
  /// Clears the metadata afterwards to avoid permanent duplication.
  Future<void> applyMetadataToProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final meta = user.userMetadata;
      if (meta == null || meta.isEmpty) return;

      await supabase.from('profiles').update({
        'first_name': meta['first_name'],
        'last_name': meta['last_name'],
        'phone_number': meta['phone_number'],
        'country': meta['country'],
        'marketing_consent': meta['marketing_consent'],
        'app_version_at_signup': meta['app_version_at_signup'],
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      // Clear metadata from auth layer to avoid permanent duplication
      await supabase.auth.updateUser(UserAttributes(data: {}));
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  Future<void> updateUserProfile(UserProfile profile) async {
    await supabase
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  Future<void> resetPassword(String email) async {
    await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: 'io.supabase.flashforward://login/reset',
    );
  }

  Future<void> updatePassword(String newPassword) async {
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  Stream<AuthState> get authStateChanges {
    return supabase.auth.onAuthStateChange;
  }

  bool isSignedIn() {
    return supabase.auth.currentUser != null;
  }

  bool isEmailConfirmed() {
    return supabase.auth.currentUser?.emailConfirmedAt != null;
  }

  Future<bool> deleteUser() async {
    try {
      await supabase.rpc('delete_current_user');
      return true;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      return false;
    }
  }
}
