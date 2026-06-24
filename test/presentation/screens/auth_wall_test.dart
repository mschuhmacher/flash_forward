import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/presentation/widgets/auth_wall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_auth_service.dart';

/// A host with one button that calls requireAuth and stashes the future, so a
/// test can both trigger the wall and await its result.
Widget _host(AuthProvider auth, void Function(Future<bool>) capture) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                capture(requireAuth(context, message: 'save your work')),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('authenticated → no sheet, resolves true', (tester) async {
    final auth = AuthProvider(authService: FakeAuthService(signedIn: true));
    late Future<bool> result;
    await tester.pumpWidget(_host(auth, (f) => result = f));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.textContaining('save your work'), findsNothing);
    expect(await result, true);
  });

  testWidgets('guest → sheet shows; Not now resolves false', (tester) async {
    final auth = AuthProvider(authService: FakeAuthService(signedIn: false));
    late Future<bool> result;
    await tester.pumpWidget(_host(auth, (f) => result = f));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Sheet is up with the templated message and the three actions.
    expect(find.textContaining('save your work'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(await result, false);
  });
}
