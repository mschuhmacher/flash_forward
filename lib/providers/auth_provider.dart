import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/models/user_profile.dart';
import 'package:flash_forward/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserProfile? _userProfile;
  bool _isLoading = false;
  String? _errorMessage;
  String? _pendingSignupPassword;

  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _authService.isSignedIn();
  bool get isEmailConfirmed => _authService.isEmailConfirmed();
  String? get userId => _userProfile?.id;

  /// Initialize auth state - call this on app startup
  Future<void> init() async {
    if (isAuthenticated) {
      await loadUserProfile();
    }
  }

  /// Load the current user's profile from Supabase
  Future<void> loadUserProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      _userProfile = await _authService.getCurrentUserProfile();
      _errorMessage = null;
    } catch (e, stackTrace) {
      _errorMessage = e.toString();
      Sentry.captureException(e, stackTrace: stackTrace);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Sign up a new user (requires email confirmation before login)
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? country,
    bool marketingConsent = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authService.signUp(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        country: country,
        marketingConsent: marketingConsent,
      );

      // Empty identities means this email is already registered
      if (response.user?.identities != null &&
          response.user!.identities!.isEmpty) {
        _errorMessage = 'This email address is already in use.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Note: User must confirm email before they can sign in
      // Don't load profile here - user isn't authenticated yet
      _isLoading = false;
      notifyListeners();
      // Temp save password here in AuthProvider for polling the confirmation status
      _pendingSignupPassword = password;
      return true;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign in an existing user
  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signIn(email: email, password: password);
      await loadUserProfile();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> trySignInAfterConfirmation({
    required String email,
    required String password,
  }) async {
    try {
      final signInSuccess = await _authService.trySignIn(
        email: email,
        password: password,
      );

      if (signInSuccess) {
        await loadUserProfile();
      }
      return signInSuccess;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> resendConfirmationEmail(String email) async {
    await _authService.resendConfirmationEmail(email: email);
  }

  /// Silently polls for email confirmation using the password stored during signup.
  /// Does not modify loading/error state.
  Future<EmailStatus> pollForEmailConfirmation(String email) async {
    final password = _pendingSignupPassword;
    if (password == null) return EmailStatus.foundButNotConfirmed;

    final status = await _authService.checkEmailStatus(email, password);
    if (status == EmailStatus.confirmed) {
      _pendingSignupPassword = null;
    }
    return status;
  }

  /// Clears the in-memory signup password. Call from EmailConfirmationScreen.dispose().
  void clearPendingSignupPassword() {
    _pendingSignupPassword = null;
  }

  /// Sign out the current user
  Future<void> signOut() async {
    await _authService.signOut();
    _userProfile = null;
    notifyListeners();
  }

  Future<void> resetPassword(email) async {
    await _authService.resetPassword(email);
    notifyListeners();
  }

  /// Update the user's profile
  Future<void> updateProfile(UserProfile updatedProfile) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.updateUserProfile(updatedProfile);
      _userProfile = updatedProfile;
      _errorMessage = null;
    } catch (e, stackTrace) {
      _errorMessage = e.toString();
      Sentry.captureException(e, stackTrace: stackTrace);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Delete the current user
  Future<void> deleteUser() async {
    await _authService.deleteUser();
    _userProfile = null;
    notifyListeners();
  }

  /// Clear any error messages
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
