import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flash_forward/services/supabase_config.dart';
import '../models/user_profile.dart';

class AuthService {
  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String firstName,
    String? lastName,
    String? phoneNumber,
    String? country,
    bool marketingConsent = false,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

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

      if (response.user != null) {
        await _updateProfile(
          userId: response.user!.id,
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          country: country,
          marketingConsent: marketingConsent,
          appVersionAtSignup: appVersion,
        );
      }

      return response;
    } catch (e) {
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
    } catch (e) {
      return null;
    }
  }

  Future<void> updateUserProfile(UserProfile profile) async {
    await supabase
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  Future<void> _updateProfile({
    required String userId,
    required String firstName,
    String? lastName,
    String? phoneNumber,
    String? country,
    required bool marketingConsent,
    required String appVersionAtSignup,
  }) async {
    try {
      await supabase
          .from('profiles')
          .update({
            'first_name': firstName,
            'last_name': lastName,
            'phone_number': phoneNumber,
            'country': country,
            'marketing_consent': marketingConsent,
            'app_version_at_signup': appVersionAtSignup,
          })
          .eq('id', userId);
    } catch (e) {
      print('Error updating profile: $e');
    }
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
}
