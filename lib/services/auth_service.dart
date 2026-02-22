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

      // Step 1: Create the auth user
      // Trigger will create empty profile automatically
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      // Empty identities means this email is already registered — skip profile creation
      if (response.user?.identities != null &&
          response.user!.identities!.isEmpty) {
        return response;
      }

      if (response.user != null) {
        // Create or update the profile
        try {
          // Check if profile already exists
          final existing =
              await supabase
                  .from('profiles')
                  .select()
                  .eq('id', response.user!.id)
                  .maybeSingle();

          final profileData = {
            'first_name': firstName,
            'last_name': lastName,
            'phone_number': phoneNumber,
            'country': country,
            'marketing_consent': marketingConsent,
            'app_version_at_signup': appVersion,
            'updated_at': DateTime.now().toIso8601String(),
          };

          if (existing == null) {
            // No profile row exists - INSERT it
            await supabase.from('profiles').insert({
              'id': response.user!.id,
              'email': email,
              'account_created_at': DateTime.now().toIso8601String(),
              ...profileData,
            });
          } else {
            // Profile exists - UPDATE it
            await supabase
                .from('profiles')
                .update(profileData)
                .eq('id', response.user!.id);
          }
        } catch (profileError, stackTrace) {
          Sentry.captureException(profileError, stackTrace: stackTrace);
          // Don't fail the entire signup
        }
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

  Future<void> updateUserProfile(UserProfile profile) async {
    await supabase
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  Future<void> resetPassword(String email) async {
    await supabase.auth.resetPasswordForEmail(email);
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
}
