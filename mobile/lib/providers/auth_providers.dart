import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the current Firebase Auth state (null = signed out, User = signed in)
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Provides the current user synchronously (may be null)
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Auth service for login/logout actions with proper FirebaseAuthException handling
class AuthNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<UserCredential> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      state = const AsyncValue.data(null);
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        state = AsyncValue.error(
          Exception('No user found for that email.'),
          StackTrace.current,
        );
      } else if (e.code == 'wrong-password') {
        state = AsyncValue.error(
          Exception('Wrong password provided.'),
          StackTrace.current,
        );
      } else {
        state = AsyncValue.error(e, StackTrace.current);
      }
      rethrow;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      state = const AsyncValue.data(null);
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        state = AsyncValue.error(
          Exception('The password provided is too weak.'),
          StackTrace.current,
        );
      } else if (e.code == 'email-already-in-use') {
        state = AsyncValue.error(
          Exception('An account already exists for that email.'),
          StackTrace.current,
        );
      } else {
        state = AsyncValue.error(e, StackTrace.current);
      }
      rethrow;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await FirebaseAuth.instance.signOut();
    });
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AsyncValue<void>>(
  AuthNotifier.new,
);
