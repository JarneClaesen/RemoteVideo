import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import '../models/user_model.dart';
import '../services/pocketbase_service.dart';

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
  final PocketBaseService _pocketBaseService = PocketBaseService();

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAuthenticating => _status == AuthStatus.authenticating;

  AuthProvider() {
    // Check if user is already authenticated
    _checkCurrentUser();
  }

  Future<void> _checkCurrentUser() async {
    try {
      if (PocketBaseService.client.authStore.isValid) {
        final userId = PocketBaseService.client.authStore.model.id;
        await _getUserData(userId);
      } else {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  Future<void> _getUserData(String userId) async {
    try {
      final record = await PocketBaseService.client.collection('users').getOne(userId);

      _user = UserModel.fromPocketBase(record);
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

      final response = await _pocketBaseService.signIn(
        email: email,
        password: password,
      );

      if (response.token.isNotEmpty) {
        await _getUserData(response.record.id);
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

      final response = await _pocketBaseService.signUp(
        email: email,
        password: password,
        username: username,
      );

      if (response.token.isNotEmpty) {
        await _getUserData(response.record.id);
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
      await _pocketBaseService.signOut();
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }
}