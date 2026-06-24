part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthSignedUp extends AuthEvent {
  final String email;
  final String password;
  final String? firstName;
  final String? lastName;

  const AuthSignedUp({
    required this.email,
    required this.password,
    this.firstName,
    this.lastName,
  });

  @override
  List<Object?> get props => [email, password, firstName, lastName];
}

class AuthSignedIn extends AuthEvent {
  final String email;
  final String password;

  const AuthSignedIn({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

class AuthSignedInWithGoogle extends AuthEvent {
  const AuthSignedInWithGoogle();
}

class AuthSignedOut extends AuthEvent {
  const AuthSignedOut();
}

class AuthProfileCompleted extends AuthEvent {
  const AuthProfileCompleted();
}
