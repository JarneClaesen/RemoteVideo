// lib/providers/lobby_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../models/file_transfer_progress.dart';
import '../models/lobby_model.dart';
import '../services/supabase_service.dart';

enum LobbyStatus {
  initial,
  loading,
  ready,
  error,
  videoUploading,
  videoDownloading,
  videoReady,
}

class LobbyProvider extends ChangeNotifier {
  LobbyStatus _status = LobbyStatus.initial;
  LobbyModel? _currentLobby;
  String? _errorMessage;
  bool _isHost = false;
  VideoPlayerController? _videoController;
  File? _localVideoFile;
  List<LobbyModel> _availableLobbies = [];
  StreamSubscription? _lobbySubscription;
  StreamSubscription? _participantsSubscription;
  FileTransferProgress? _uploadProgress;
  FileTransferProgress? _downloadProgress;
  Timer? _progressTimer;

  final SupabaseService _supabaseService = SupabaseService();

  LobbyStatus get status => _status;
  LobbyModel? get currentLobby => _currentLobby;
  String? get errorMessage => _errorMessage;
  bool get isHost => _isHost;
  VideoPlayerController? get videoController => _videoController;
  File? get localVideoFile => _localVideoFile;
  List<LobbyModel> get availableLobbies => _availableLobbies;
  FileTransferProgress? get uploadProgress => _uploadProgress;
  FileTransferProgress? get downloadProgress => _downloadProgress;

  LobbyProvider() {
    loadAvailableLobbies();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoController?.dispose();
    _lobbySubscription?.cancel();
    _participantsSubscription?.cancel();
    super.dispose();
  }

  // Load all available active lobbies
  Future<void> loadAvailableLobbies() async {
    try {
      print('Loading available lobbies...');
      _status = LobbyStatus.loading;
      notifyListeners();

      // Remove the is_active filter that doesn't exist
      print('Fetching lobbies from Supabase...');
      final response = await SupabaseService.client
          .from('lobbies')
          .select()
          .order('created_at', ascending: false);
      print('Received ${(response as List).length} lobbies from database');

      List<LobbyModel> lobbies = (response)
          .map((data) => LobbyModel.fromJson(data))
          .toList();
      print('Parsed ${lobbies.length} lobby models');

      // For each lobby, fetch its participants
      print('Fetching participants for each lobby...');
      for (var i = 0; i < lobbies.length; i++) {
        print('Fetching participants for lobby ID: ${lobbies[i].id}');
        final participantsResponse = await SupabaseService.client
            .from('lobby_participants')
            .select('user_id')
            .eq('lobby_id', lobbies[i].id);

        final participants = (participantsResponse as List)
            .map((data) => data['user_id'] as String)
            .toList();
        print('Found ${participants.length} participants for lobby ID: ${lobbies[i].id}');

        lobbies[i] = lobbies[i].copyWith(participants: participants);
      }

      _availableLobbies = lobbies;
      _status = LobbyStatus.ready;
      print('Successfully loaded ${lobbies.length} lobbies with participants');
      notifyListeners();
    } catch (e) {
      print('ERROR: Failed to load lobbies: $e');
      _status = LobbyStatus.error;
      _errorMessage = 'Failed to load lobbies: ${e.toString()}';
      notifyListeners();
    }
  }

  // Create a new lobby
  Future<bool> createLobby({
    required String name,
    required String hostId,
  }) async {
    try {
      _status = LobbyStatus.loading;
      notifyListeners();

      final String lobbyId = const Uuid().v4();
      final now = DateTime.now();

      // Create minimal lobby data matching database schema
      await SupabaseService.client
          .from('lobbies')
          .insert({
        'id': lobbyId,
        'name': name,
        'host_id': hostId,
        // created_at and updated_at are handled by the database defaults
      });

      // Add host as participant
      await SupabaseService.client
          .from('lobby_participants')
          .insert({
        'lobby_id': lobbyId,
        'user_id': hostId,
      });

      // Create local model
      _currentLobby = LobbyModel(
        id: lobbyId,
        name: name,
        hostId: hostId,
        createdAt: now,
        updatedAt: now,
        participants: [hostId],
      );

      _isHost = true;
      _status = LobbyStatus.ready;

      // Setup real-time updates
      _setupLobbySubscription(lobbyId);

      notifyListeners();
      return true;
    } catch (e) {
      _status = LobbyStatus.error;
      _errorMessage = 'Failed to create lobby: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Join an existing lobby
  Future<bool> joinLobby({
    required String lobbyId,
    required String userId,
  }) async {
    try {
      _status = LobbyStatus.loading;
      notifyListeners();

      // Get lobby details
      final response = await SupabaseService.client
          .from('lobbies')
          .select()
          .eq('id', lobbyId)
          .single();

      // Get participants
      final participantsResponse = await SupabaseService.client
          .from('lobby_participants')
          .select('user_id')
          .eq('lobby_id', lobbyId);

      final participants = (participantsResponse as List)
          .map((data) => data['user_id'] as String)
          .toList();

      // Check if user is host
      final lobby = LobbyModel.fromJson(response);
      _isHost = lobby.hostId == userId;

      // Add user as participant if not already
      if (!participants.contains(userId)) {
        await SupabaseService.client
            .from('lobby_participants')
            .insert({
          'lobby_id': lobbyId,
          'user_id': userId,
        });
        participants.add(userId);
      }

      _currentLobby = lobby.copyWith(participants: participants);

      // Setup subscriptions
      _setupLobbySubscription(lobbyId);

      // Handle video if exists
      if (_currentLobby?.videoUrl != null && !_isHost) {
        await _downloadVideo();
      } else {
        _status = LobbyStatus.ready;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _status = LobbyStatus.error;
      _errorMessage = 'Failed to join lobby: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Leave the current lobby
  Future<bool> leaveLobby(String userId) async {
    try {
      if (_currentLobby == null) return true;

      // Remove from participants table
      await SupabaseService.client
          .from('lobby_participants')
          .delete()
          .eq('lobby_id', _currentLobby!.id)
          .eq('user_id', userId);

      // If host, delete lobby
      if (_isHost) {
        await SupabaseService.client
            .from('lobbies')
            .delete()
            .eq('id', _currentLobby!.id);
      }

      // Clean up resources
      _lobbySubscription?.cancel();
      _participantsSubscription?.cancel();
      _videoController?.dispose();
      _videoController = null;
      _localVideoFile = null;
      _currentLobby = null;
      _isHost = false;
      _status = LobbyStatus.initial;

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to leave lobby: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Upload a video (host only)
  Future<bool> uploadVideo(File videoFile) async {
    if (!_isHost || _currentLobby == null) return false;

    try {
      _status = LobbyStatus.videoUploading;

      // Get file size
      final fileSize = await videoFile.length();

      // Initialize progress
      _uploadProgress = FileTransferProgress(
        bytesTransferred: 0,
        totalBytes: fileSize,
        speed: 0,
        lastUpdated: DateTime.now(),
      );

      notifyListeners();

      // Set up progress simulation
      _progressTimer?.cancel();

      // Simulate upload progress
      int lastBytes = 0;
      DateTime lastTime = DateTime.now();
      int simulatedBytesUploaded = 0;

      // Update progress every 200ms
      _progressTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
        // Simulate upload speed (around 1MB/s with some variation)
        final bytesPerSecond = 1024 * 1024 * (0.8 + 0.4 * math.Random().nextDouble());
        final bytesPerTick = (bytesPerSecond * 0.2).toInt(); // 200ms tick

        simulatedBytesUploaded += bytesPerTick;
        if (simulatedBytesUploaded > fileSize) {
          simulatedBytesUploaded = fileSize;
          // Don't cancel yet - wait for actual upload to complete
        }

        // Calculate actual speed based on time difference
        final now = DateTime.now();
        final timeDiff = now.difference(lastTime).inMilliseconds / 1000.0;
        final bytesAdded = simulatedBytesUploaded - lastBytes;
        final speed = timeDiff > 0 ? bytesAdded / timeDiff : 0;

        // Update progress
        _uploadProgress = FileTransferProgress(
          bytesTransferred: simulatedBytesUploaded,
          totalBytes: fileSize,
          speed: speed,
          lastUpdated: now,
        );

        lastBytes = simulatedBytesUploaded;
        lastTime = now;

        notifyListeners();
      });

      // Start the actual upload
      final fileName = '${_currentLobby!.id}_${path.basename(videoFile.path)}';
      final stopwatch = Stopwatch()..start();

      try {
        // Perform the actual upload
        await SupabaseService.client
            .storage
            .from('videos')
            .upload(fileName, videoFile);

        // Get the public URL
        final videoUrl = SupabaseService.client
            .storage
            .from('videos')
            .getPublicUrl(fileName);

        // Update the lobby with the video URL
        await SupabaseService.client
            .from('lobbies')
            .update({
          'video_url': videoUrl,
          'video_file_name': fileName,
        })
            .eq('id', _currentLobby!.id);

        // Update local state
        _currentLobby = _currentLobby!.copyWith(
          videoUrl: videoUrl,
          videoFileName: fileName,
        );

        // Set up video player with the local file
        _localVideoFile = videoFile;
        await _initializeVideoPlayer(videoFile.path);

        // Cancel the progress timer and set final progress
        _progressTimer?.cancel();
        _uploadProgress = FileTransferProgress(
          bytesTransferred: fileSize,
          totalBytes: fileSize,
          speed: fileSize / (stopwatch.elapsedMilliseconds > 0 ? stopwatch.elapsedMilliseconds : 1) * 1000,
          lastUpdated: DateTime.now(),
        );

        _status = LobbyStatus.videoReady;
        notifyListeners();
        return true;
      } catch (e) {
        _progressTimer?.cancel();
        _status = LobbyStatus.error;
        _errorMessage = 'Failed to upload video: ${e.toString()}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _progressTimer?.cancel();
      _status = LobbyStatus.error;
      _errorMessage = 'Failed to upload video: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Download the video for participants
  Future<void> _downloadVideo() async {
    if (_currentLobby?.videoUrl == null) {
      print('Download canceled: Video URL is null');
      return;
    }

    try {
      print('Starting video download process');
      _status = LobbyStatus.videoDownloading;

      // Get the app's temporary directory
      final appDir = await getTemporaryDirectory();
      final filePath = '${appDir.path}/${_currentLobby!.videoFileName}';
      print('Video will be stored at: $filePath');

      // Check if file already exists
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        print('Existing file size: ${fileSize} bytes');

        // If file is suspiciously small (less than 1KB), consider it invalid
        if (fileSize < 1024) {
          print('File too small, deleting and re-downloading');
          await file.delete();
          // Continue with download code
        } else {
          _localVideoFile = file;
          print('Initializing video player with existing file');
          await _initializeVideoPlayer(filePath);
          _status = LobbyStatus.videoReady;
          notifyListeners();
          return;
        }
      }

      // Initialize download progress
      _downloadProgress = FileTransferProgress(
        bytesTransferred: 0,
        totalBytes: null, // Unknown initially
        speed: 0,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();

      try {
        final stopwatch = Stopwatch()..start();
        print('Downloading video from Supabase');

        // Extract just the filename from the video URL
        final String? fileName = _currentLobby!.videoFileName;
        print('Downloading file: $fileName from "videos" bucket');

        // Try to get file size via HEAD request first
        int? totalSize;
        try {
          final downloadUrl = _currentLobby!.videoUrl;
          if (downloadUrl != null) {
            final headResponse = await http.head(Uri.parse(downloadUrl));
            if (headResponse.statusCode == 200) {
              final contentLength = headResponse.headers['content-length'];
              if (contentLength != null) {
                totalSize = int.parse(contentLength);
                print('File size from HEAD request: $totalSize bytes');

                // Update progress with total size
                _downloadProgress = FileTransferProgress(
                  bytesTransferred: 0,
                  totalBytes: totalSize,
                  speed: 0,
                  lastUpdated: DateTime.now(),
                );
                notifyListeners();
              }
            }
          }
        } catch (e) {
          print('Failed to get file size via HEAD: $e');
          // Continue without size
        }

        // Use an estimated size if not available (50MB is a reasonable video size)
        totalSize ??= 50 * 1024 * 1024;

        // Set up progress simulation
        _progressTimer?.cancel();

        // Track download progress
        int lastBytes = 0;
        DateTime lastTime = DateTime.now();
        int simulatedBytesDownloaded = 0;

        // Update progress every 200ms
        _progressTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
          // Simulate download speed (around 2MB/s with some variation)
          final bytesPerSecond = 2 * 1024 * 1024 * (0.8 + 0.4 * math.Random().nextDouble());
          final bytesPerTick = (bytesPerSecond * 0.2).toInt(); // 200ms tick

          simulatedBytesDownloaded += bytesPerTick;
          if (simulatedBytesDownloaded > totalSize!) {
            simulatedBytesDownloaded = totalSize;
            // Don't cancel yet - wait for actual download to complete
          }

          // Calculate actual speed based on time difference
          final now = DateTime.now();
          final timeDiff = now.difference(lastTime).inMilliseconds / 1000.0;
          final bytesAdded = simulatedBytesDownloaded - lastBytes;
          final speed = timeDiff > 0 ? bytesAdded / timeDiff : 0;

          // Update progress
          _downloadProgress = FileTransferProgress(
            bytesTransferred: simulatedBytesDownloaded,
            totalBytes: totalSize,
            speed: speed,
            lastUpdated: now,
          );

          lastBytes = simulatedBytesDownloaded;
          lastTime = now;

          notifyListeners();
        });

        // Perform the actual download
        final bytes = await SupabaseService.client
            .storage
            .from('videos')
            .download(fileName!);

        // Cancel the progress timer
        _progressTimer?.cancel();

        print('Download completed in ${stopwatch.elapsedMilliseconds}ms');
        print('Received ${bytes.length} bytes');

        // Update with final progress
        _downloadProgress = FileTransferProgress(
          bytesTransferred: bytes.length,
          totalBytes: bytes.length,
          speed: bytes.length / (stopwatch.elapsedMilliseconds > 0 ? stopwatch.elapsedMilliseconds : 1) * 1000,
          lastUpdated: DateTime.now(),
        );
        notifyListeners();

        print('Writing file to disk');
        await file.writeAsBytes(bytes);
        print('File written successfully, size: ${bytes.length} bytes');

        _localVideoFile = file;
        print('Initializing video player with downloaded file');
        await _initializeVideoPlayer(filePath);

        _status = LobbyStatus.videoReady;
        print('Video download and initialization completed in ${stopwatch.elapsedMilliseconds}ms');
      } catch (e) {
        _progressTimer?.cancel();
        print('Error during download/write process: $e');
        print('Error details: ${e.toString()}');
        _status = LobbyStatus.error;
        _errorMessage = 'Failed to download video: ${e.toString()}';
      }
      notifyListeners();
    } catch (e) {
      _progressTimer?.cancel();
      print('Error in _downloadVideo method: $e');
      print('Stack trace: ${StackTrace.current}');
      _status = LobbyStatus.error;
      _errorMessage = 'Failed to download video: ${e.toString()}';
      notifyListeners();
    }
  }


  // Initialize the video player
  Future<void> _initializeVideoPlayer(String filePath) async {
    try {
      await _videoController?.dispose();

      // Create the controller
      _videoController = VideoPlayerController.file(File(filePath));

      // Wait for initialization
      await _videoController!.initialize();

      // You can set additional properties after initialization
      _videoController!.setLooping(true);

      notifyListeners();
    } catch (e) {
      print('ERROR: Failed to initialize video player: ${e.toString()}');
      _errorMessage = 'Failed to initialize video player: ${e.toString()}';
      _status = LobbyStatus.error;
      notifyListeners();
    }
  }


  // Play the video (host only)
  Future<void> playVideo() async {
    if (!_isHost || _videoController == null || _currentLobby == null) return;

    try {
      await _videoController!.play();

      // Update the lobby state
      await SupabaseService.client
          .from('lobbies')
          .update({
        'is_playing': true,
        'video_position': _videoController!.value.position.inMilliseconds,
      })
          .eq('id', _currentLobby!.id);

      _currentLobby = _currentLobby!.copyWith(
        isPlaying: true,
        videoPosition: _videoController!.value.position.inMilliseconds,
      );

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to play video: ${e.toString()}';
      notifyListeners();
    }
  }

  // Pause the video (host only)
  Future<void> pauseVideo() async {
    if (!_isHost || _videoController == null || _currentLobby == null) return;

    try {
      await _videoController!.pause();

      // Update the lobby state
      await SupabaseService.client
          .from('lobbies')
          .update({
        'is_playing': false,
        'video_position': _videoController!.value.position.inMilliseconds,
      })
          .eq('id', _currentLobby!.id);

      _currentLobby = _currentLobby!.copyWith(
        isPlaying: false,
        videoPosition: _videoController!.value.position.inMilliseconds,
      );

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to pause video: ${e.toString()}';
      notifyListeners();
    }
  }

  // Seek the video to a specific position (host only)
  Future<void> seekVideo(Duration position) async {
    if (!_isHost || _videoController == null || _currentLobby == null) return;

    try {
      await _videoController!.seekTo(position);

      // Update the lobby state
      await SupabaseService.client
          .from('lobbies')
          .update({
        'video_position': position.inMilliseconds,
      })
          .eq('id', _currentLobby!.id);

      _currentLobby = _currentLobby!.copyWith(
        videoPosition: position.inMilliseconds,
      );

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to seek video: ${e.toString()}';
      notifyListeners();
    }
  }

  // Setup real-time subscription to lobby updates
  void _setupLobbySubscription(String lobbyId) {
    _lobbySubscription?.cancel();
    _participantsSubscription?.cancel();

    // Subscribe to lobby changes
    _lobbySubscription = SupabaseService.client
        .from('lobbies')
        .stream(primaryKey: ['id'])
        .eq('id', lobbyId)
        .listen((data) async {
      if (data.isEmpty) return;

      final updatedLobby = LobbyModel.fromJson(data.first);
      final previousLobby = _currentLobby;

      // Keep current participants
      final currentParticipants = _currentLobby?.participants ?? [];
      _currentLobby = updatedLobby.copyWith(participants: currentParticipants);

      // Handle video controller updates
      if (_videoController != null) {
        // Play/pause state changes
        if (previousLobby?.isPlaying != updatedLobby.isPlaying) {
          if (updatedLobby.isPlaying) {
            await _videoController!.play();
          } else {
            await _videoController!.pause();
          }
        }

        // Position changes for non-hosts
        if (!_isHost &&
            previousLobby?.videoPosition != updatedLobby.videoPosition &&
            (previousLobby?.videoPosition == null ||
                (updatedLobby.videoPosition - previousLobby!.videoPosition).abs() > 500)) {
          await _videoController!.seekTo(
            Duration(milliseconds: updatedLobby.videoPosition),
          );
        }
      }

      // New video detection
      if (!_isHost &&
          previousLobby?.videoUrl == null &&
          updatedLobby.videoUrl != null) {
        await _downloadVideo();
      }

      notifyListeners();
    });

    // Add subscription for participants
    _participantsSubscription = SupabaseService.client
        .from('lobby_participants')
        .stream(primaryKey: ['id'])
        .eq('lobby_id', lobbyId)
        .listen((data) async {
      if (_currentLobby == null) return;

      final participants = data.map((item) => item['user_id'] as String).toList();
      _currentLobby = _currentLobby!.copyWith(participants: participants);
      notifyListeners();
    });
  }
}