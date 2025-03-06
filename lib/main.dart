import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:synced_video/theme/app_theme.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'services/pocketbase_service.dart';
import 'providers/auth_provider.dart';
import 'providers/lobby_provider.dart';
import 'screens/auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize PocketBase
  await PocketBaseService.initialize();

  // Initialize video players
  MediaKit.ensureInitialized();
  VideoPlayerMediaKit.ensureInitialized(
      android: false,
      iOS: false,
      macOS: false,
      windows: true,
      linux: true,
      web: false
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
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const AuthWrapper(),
      ),
    );
  }
}