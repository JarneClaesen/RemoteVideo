// lib/services/pocketbase_service.dart
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class PocketBaseService {
  static PocketBase? _pb;
  static String? _baseUrl;

  static String getPlatformUrl(String url) {
    if (!kIsWeb && Platform.isAndroid) {
      // Replace localhost with 10.0.2.2 for Android
      return url.replaceAll('localhost', '10.0.2.2');
    }
    return url;
  }

  static Future<void> initialize() async {
    final String url = kIsWeb
        ? 'http://localhost:8090'
        : Platform.isWindows
        ? 'http://localhost:8090'
        : 'http://10.0.2.2:8090';

    _baseUrl = url;
    _pb = PocketBase(url);

    // Try to auto-authenticate from saved state
    try {
      if (_pb!.authStore.isValid) {
        // Refresh the auth state
        await _pb!.collection('users').authRefresh();
      }
    } catch (e) {
      // Clear auth if refresh fails
      _pb!.authStore.clear();
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
}