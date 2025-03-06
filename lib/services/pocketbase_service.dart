// lib/services/pocketbase_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketbase/pocketbase.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class PocketBaseService {
  static PocketBase? _pb;
  static String? _baseUrl;
  static const String _tokenKey = 'pocketbase_auth_token';
  static final _secureStorage = FlutterSecureStorage();

  static String getPlatformUrl(String url) {
    if (!kIsWeb && Platform.isAndroid) {
      // Replace localhost with 10.0.2.2 for Android
      return url.replaceAll('localhost', '10.0.2.2');
    }
    return url;
  }

  // Token storage methods
  static Future<String?> _getToken() async {
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (e) {
      debugPrint('Error retrieving token: $e');
      return null;
    }
  }

  static Future<void> _saveToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('Error saving token: $e');
    }
  }

  static Future<void> _deleteToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('Error deleting token: $e');
    }
  }

  static Future<void> initialize() async {
    final String url = kIsWeb
        ? 'http://localhost:8090'
        : Platform.isWindows
        ? 'http://localhost:8090'
        : 'http://10.0.2.2:8090';

    _baseUrl = url;

    // Create custom auth store that persists tokens
    final token = await _getToken();
    final customAuthStore = AsyncAuthStore(
      initial: token,
      save: _saveToken,
      clear: _deleteToken,
    );

    // Initialize PocketBase with the custom auth store
    _pb = PocketBase(url, authStore: customAuthStore);

    // Try to auto-authenticate from saved state
    try {
      if (_pb!.authStore.isValid) {
        // Refresh the auth state
        await _pb!.collection('users').authRefresh();
        debugPrint('Auth refreshed successfully');
      }
    } catch (e) {
      // Clear auth if refresh fails
      _pb!.authStore.clear();
      debugPrint('Failed to refresh auth: $e');
    }
  }

  static PocketBase get client {
    if (_pb == null) {
      throw Exception('PocketBase client has not been initialized');
    }
    return _pb!;
  }

  static String get baseUrl {
    if (_baseUrl == null) {
      throw Exception('PocketBase URL has not been initialized');
    }
    return _baseUrl!;
  }

  // Authentication methods
  Future<RecordAuth> signIn({required String email, required String password}) async {
    return await client.collection('users').authWithPassword(
      email,
      password,
    );
  }

  Future<RecordAuth> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    final userData = {
      'email': email,
      'password': password,
      'passwordConfirm': password,
      'username': username ?? email.split('@')[0],
      'is_host': false,
    };

    // First create the user
    await client.collection('users').create(body: userData);

    // Then authenticate with the created user credentials
    return await client.collection('users').authWithPassword(
      email,
      password,
    );
  }

  Future<void> signOut() async {
    client.authStore.clear();
  }

  // Get file URL
  static String getFileUrl(String collectionId, String recordId, String fileName) {
    return '$baseUrl/api/files/$collectionId/$recordId/$fileName';
  }

  // Helper to check authentication status
  static bool isAuthenticated() {
    return _pb != null && _pb!.authStore.isValid;
  }
}