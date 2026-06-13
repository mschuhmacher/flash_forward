import 'package:flash_forward/features/auth/auth_service.dart';

/// Constructible without Supabase.initialize() — the real AuthService only
/// touches the supabase global inside its methods, and the two read methods
/// the UI cares about are overridden here to return canned values.
class FakeAuthService extends AuthService {
  FakeAuthService({this.signedIn = false, this.emailConfirmed = true});

  bool signedIn;
  bool emailConfirmed;

  @override
  bool isSignedIn() => signedIn;

  @override
  bool isEmailConfirmed() => emailConfirmed;
}
