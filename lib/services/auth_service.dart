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
    required String lastName,
    String? phoneNumber,
    String? country,
    bool marketingConsent = false,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      print('=== SIGNUP START ===');
      print('Email: $email');
      print('First Name: $firstName');
      print('Last Name: $lastName');

      // Step 1: Create the auth user
      // Trigger will create empty profile automatically
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      print('Auth user created: ${response.user?.id}');
      print('Session exists: ${response.session != null}');

      if (response.user != null) {
        // Step 2: Wait briefly for trigger to create the profile row
        await Future.delayed(const Duration(milliseconds: 500));

        // Step 3: Now UPDATE the profile with user data (not INSERT)
        // User is authenticated, so RLS allows this UPDATE
        print('Updating profile with user data...');

        try {
          await supabase
              .from('profiles')
              .update({
                'first_name': firstName,
                'last_name': lastName,
                'phone_number': phoneNumber,
                'country': country,
                'marketing_consent': marketingConsent,
                'app_version_at_signup': appVersion,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', response.user!.id);

          print('Profile updated successfully');
        } catch (updateError) {
          print('!!! Error updating profile: $updateError');
          // Don't fail the entire signup
        }
      }

      print('=== SIGNUP COMPLETE ===');
      return response;
    } catch (e) {
      print('!!! SIGNUP ERROR: $e');
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

  // Future<void> _updateProfile({
  //   required String userId,
  //   required String firstName,
  //   required String lastName,
  //   String? phoneNumber,
  //   String? country,
  //   required bool marketingConsent,
  //   required String appVersionAtSignup,
  // }) async {
  //   try {
  //     print('=== UPDATE PROFILE ===');
  //     print('User ID: $userId');
  //     print('First Name: $firstName');
  //     print('Last Name: $lastName');

  //     // Give the trigger time to create the profile row
  //     await Future.delayed(const Duration(milliseconds: 500));

  //     // Check if profile exists
  //     final existing =
  //         await supabase
  //             .from('profiles')
  //             .select()
  //             .eq('id', userId)
  //             .maybeSingle();

  //     print('Existing profile found: ${existing != null}');

  //     final profileData = {
  //       'first_name': firstName,
  //       'last_name': lastName,
  //       'phone_number': phoneNumber,
  //       'country': country,
  //       'marketing_consent': marketingConsent,
  //       'app_version_at_signup': appVersionAtSignup,
  //     };

  //     if (existing == null) {
  //       print('No profile found, inserting...');
  //       // Profile doesn't exist yet, insert it manually
  //       await supabase.from('profiles').insert({
  //         'id': userId,
  //         'email': supabase.auth.currentUser?.email ?? '',
  //         ...profileData,
  //       });
  //       print('Profile inserted');
  //     } else {
  //       print('Profile exists, updating...');
  //       // Profile exists, update it
  //       await supabase.from('profiles').update(profileData).eq('id', userId);
  //       print('Profile updated');
  //     }

  //     print('=== PROFILE UPDATE COMPLETE ===');
  //   } catch (e) {
  //     print('!!! ERROR updating profile: $e');
  //     // Don't rethrow - we want signup to succeed even if profile update fails
  //   }
  // }

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
