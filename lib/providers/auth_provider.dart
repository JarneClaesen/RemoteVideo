// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../services/supabase_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  authenticating,
  authenticated,
  error,
}

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _errorMessage;
  final SupabaseService _supabaseService = SupabaseService();

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAuthenticating => _status == AuthStatus.authenticating;

  AuthProvider() {
    // Check if user is already authenticated
    _checkCurrentUser();

    // Listen to auth state changes
    SupabaseService.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        _getUserData(session.user.id);
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });
  }

  Future<void> _checkCurrentUser() async {
    final session = SupabaseService.client.auth.currentSession;

    if (session != null) {
      await _getUserData(session.user.id);
    } else {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> _getUserData(String userId) async {
    try {
      final response = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      _user = UserModel.fromJson(response);
      _status = AuthStatus.authenticated;
      notifyListeners();
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    try {
      _status = AuthStatus.authenticating;
      _errorMessage = null;
      notifyListeners();

      final response = await _supabaseService.signIn(
        email: email,
        password: password,
      );

      if (response.session != null) {
        await _getUserData(response.user!.id);
        return true;
      }

      _status = AuthStatus.error;
      _errorMessage = 'Authentication failed';
      notifyListeners();
      return false;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    try {
      _status = AuthStatus.authenticating;
      _errorMessage = null;
      notifyListeners();

      final response = await _supabaseService.signUp(
        email: email,
        password: password,
        username: username,
      );

      if (response.session != null) {
        await _getUserData(response.user!.id);
        return true;
      }

      _status = AuthStatus.error;
      _errorMessage = 'Registration failed';
      notifyListeners();
      return false;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _supabaseService.signOut();
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}