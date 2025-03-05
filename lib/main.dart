// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synced_video/providers/lobby_provider.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseService.initialize();
  VideoPlayerMediaKit.ensureInitialized(
    android: true,          // default: false    -    dependency: media_kit_libs_android_video
    iOS: true,              // default: false    -    dependency: media_kit_libs_ios_video
    macOS: true,            // default: false    -    dependency: media_kit_libs_macos_video
    windows: true,          // default: false    -    dependency: media_kit_libs_windows_video
    linux: true,
    web: true
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LobbyProvider()),
      ],
      child: MaterialApp(
        title: 'Video Sync App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    switch (authProvider.status) {
      case AuthStatus.authenticated:
        return const HomeScreen();
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        return const LoginScreen();
      case AuthStatus.initial:
      case AuthStatus.authenticating:
      default:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
    }
  }
}