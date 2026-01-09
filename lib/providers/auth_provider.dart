import 'package:flutter/material.dart';
import 'package:flash_forward/models/user_profile.dart';
import 'package:flash_forward/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserProfile? _userProfile;
  bool _isLoading = false;
  String? _errorMessage;

  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _authService.isSignedIn();
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
    } catch (e) {
      _errorMessage = e.toString();
      print('Error loading user profile: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Sign up a new user
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
      await _authService.signUp(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        country: country,
        marketingConsent: marketingConsent,
      );

      await loadUserProfile();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
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
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    await _authService.signOut();
    _userProfile = null;
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
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Clear any error messages
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
