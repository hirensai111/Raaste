import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:raaste/features/auth/domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc(this._authRepository) : super(const AuthInitial()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignedUp>(_onSignedUp);
    on<AuthSignedIn>(_onSignedIn);
    on<AuthSignedInWithGoogle>(_onSignedInWithGoogle);
    on<AuthSignedOut>(_onSignedOut);
    on<AuthProfileCompleted>(_onProfileCompleted);

    _authRepository.authStateChanges.listen((isAuthenticated) {
      if (isAuthenticated) {
        add(const AuthStarted());
      }
    });
  }

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    await emit.onEach(
      _authRepository.authStateChanges,
      onData: (isAuthenticated) {
        if (isAuthenticated) {
          emit(const AuthAuthenticated());
        } else {
          emit(const AuthUnauthenticated());
        }
      },
    );
  }

  Future<void> _onSignedUp(
    AuthSignedUp event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _authRepository.signUpWithEmail(
        email: event.email,
        password: event.password,
        firstName: event.firstName,
        lastName: event.lastName,
      );
      emit(const AuthAuthenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignedIn(
    AuthSignedIn event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _authRepository.signInWithEmail(
        email: event.email,
        password: event.password,
      );
      emit(const AuthAuthenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignedInWithGoogle(
    AuthSignedInWithGoogle event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _authRepository.signInWithGoogle();
      // OAuth flow completes via deep link; auth state change will update UI
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onSignedOut(
    AuthSignedOut event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    await _authRepository.signOut();
    emit(const AuthUnauthenticated());
  }

  Future<void> _onProfileCompleted(
    AuthProfileCompleted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthAuthenticated());
  }
}
