// lib/services/supabase_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient? _client;

  static String getPlatformUrl(String url) {
    if (!kIsWeb && Platform.isAndroid) {
      // Replace localhost with 10.0.2.2 for Android
      return url.replaceAll('localhost', '10.0.2.2');
    }
    return url;
  }

  static Future<void> initialize() async {
    final String url = kIsWeb
        ? 'http://localhost:8000'
        : Platform.isWindows
        ? 'http://localhost:8000'
        : 'http://10.0.2.2:8000';

    await Supabase.initialize(
      url: url,
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE', // Replace with your local Supabase anon key
    );

    _client = Supabase.instance.client;
  }

  static SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase client has not been initialized');
    }
    return _client!;
  }

  // Authentication methods
  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({required String email, required String password, String? username}) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
        'is_host': false,
      },
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }
}