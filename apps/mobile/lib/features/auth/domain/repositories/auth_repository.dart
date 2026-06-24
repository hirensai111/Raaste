abstract class AuthRepository {
  Stream<bool> get authStateChanges;

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  });

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signInWithGoogle();

  Future<void> signOut();

  String? get currentUserId;

  String? get currentUserEmail;
}
