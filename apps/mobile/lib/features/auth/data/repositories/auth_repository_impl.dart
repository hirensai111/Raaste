import 'package:raaste/features/auth/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepositoryImpl implements AuthRepository {
  final GoTrueClient _auth;

  AuthRepositoryImpl() : _auth = Supabase.instance.client.auth;

  @override
  Stream<bool> get authStateChanges => _auth.onAuthStateChange.map(
        (event) => event.session != null,
      );

  @override
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final data = <String, String>{};
      if (firstName != null && firstName.isNotEmpty) {
        data['first_name'] = firstName;
      }
      if (lastName != null && lastName.isNotEmpty) {
        data['last_name'] = lastName;
      }

      final response = await _auth.signUp(
        email: email,
        password: password,
        data: data.isNotEmpty ? data : null,
      );

      if (response.user == null) {
        throw Exception('Sign up failed. Please try again.');
      }

      // Sign in immediately so the user has an active session without
      // waiting for email confirmation.
      await _auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      throw _parseAuthException(e);
    }
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Sign in failed. Please check your credentials.');
      }
    } on AuthException catch (e) {
      throw _parseAuthException(e);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.raaste.raaste://callback/',
      );
    } on AuthException catch (e) {
      throw _parseAuthException(e);
    }
  }

  @override
  Future<void> signOut() async => _auth.signOut();

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentUserEmail => _auth.currentUser?.email;

  Exception _parseAuthException(AuthException e) {
    final message = e.message.toLowerCase();

    if (e.statusCode == '429' || message.contains('rate limit')) {
      return Exception(
        'Sign-ups are temporarily limited. Please try again in a few minutes, '
        'or sign in if you already have an account.',
      );
    }
    if (message.contains('invalid login credentials')) {
      return Exception('Invalid email or password.');
    }
    if (message.contains('user already registered')) {
      return Exception(
        'This email is already registered. Please sign in instead.',
      );
    }
    if (message.contains('email')) {
      return Exception('Email error: ${e.message}');
    }

    return Exception(e.message);
  }
}
