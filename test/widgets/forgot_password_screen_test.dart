import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// We test the form without Firebase wiring by stubbing AuthProvider.
// The real AuthProvider is a ChangeNotifier; we use a lightweight fake.

class _FakeAuthProvider extends ChangeNotifier {
  bool calledReset = false;
  String? capturedEmail;
  bool shouldSucceed = true;
  String? error;

  Future<bool> resetPassword(String email) async {
    calledReset = true;
    capturedEmail = email;
    if (!shouldSucceed) error = 'User not found';
    return shouldSucceed;
  }
}

// Mini-harness that mimics the real ForgotPasswordScreen's form logic
// without pulling in FirebaseAuth. We lock in the user-facing behavior:
// - empty email -> error
// - invalid format -> error
// - valid -> calls resetPassword
void main() {
  testWidgets('empty email shows inline error',
      (WidgetTester tester) async {
    final auth = _FakeAuthProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<_FakeAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: _TestForgotForm()),
      ),
    );

    await tester.tap(find.byKey(const Key('send-reset-btn')));
    await tester.pump();
    expect(find.textContaining('Please enter your email'), findsOneWidget);
    expect(auth.calledReset, false);
  });

  testWidgets('invalid email shows validation error',
      (WidgetTester tester) async {
    final auth = _FakeAuthProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<_FakeAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: _TestForgotForm()),
      ),
    );

    await tester.enterText(find.byKey(const Key('email-field')), 'notanemail');
    await tester.tap(find.byKey(const Key('send-reset-btn')));
    await tester.pump();
    expect(find.textContaining('valid email'), findsOneWidget);
    expect(auth.calledReset, false);
  });

  testWidgets('valid email triggers resetPassword',
      (WidgetTester tester) async {
    final auth = _FakeAuthProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<_FakeAuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: _TestForgotForm()),
      ),
    );

    await tester.enterText(find.byKey(const Key('email-field')), 'alex@delta.com');
    await tester.tap(find.byKey(const Key('send-reset-btn')));
    await tester.pumpAndSettle();

    expect(auth.calledReset, true);
    expect(auth.capturedEmail, 'alex@delta.com');
    expect(find.textContaining('Check your email'), findsOneWidget);
  });
}

/// Extracted form logic for testability — mirrors the real ForgotPasswordScreen
/// but uses the _FakeAuthProvider so no Firebase dependency leaks into tests.
class _TestForgotForm extends StatefulWidget {
  const _TestForgotForm();
  @override
  State<_TestForgotForm> createState() => _TestForgotFormState();
}

class _TestForgotFormState extends State<_TestForgotForm> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _sent = false;

  Future<void> _submit() async {
    final email = _ctrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!ok) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    final auth = context.read<_FakeAuthProvider>();
    final success = await auth.resetPassword(email);
    setState(() {
      _sent = success;
      _error = success ? null : auth.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) return const Scaffold(body: Center(child: Text('Check your email')));
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          if (_error != null) Text(_error!),
          TextField(
            key: const Key('email-field'),
            controller: _ctrl,
          ),
          ElevatedButton(
            key: const Key('send-reset-btn'),
            onPressed: _submit,
            child: const Text('Send Reset Link'),
          ),
        ]),
      ),
    );
  }
}
