import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../models/file_transfer_progress.dart';
import '../models/lobby_model.dart';
import '../services/pocketbase_service.dart';

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
  Timer? _lobbySubscriptionTimer;
  Timer? _participantsSubscriptionTimer;
  FileTransferProgress? _uploadProgress;
  FileTransferProgress? _downloadProgress;
  Timer? _progressTimer;
  String? _currentLobbyId;

  final PocketBaseService _pocketBaseService = PocketBaseService();

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
    if (_currentLobbyId != null) {
      PocketBaseService.client.collection('lobbies').unsubscribe(_currentLobbyId!);
    }
    _progressTimer?.cancel();
    _lobbySubscriptionTimer?.cancel();
    _participantsSubscriptionTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  // Load all available active lobbies
  Future<void> loadAvailableLobbies() async {
    try {
      print('Loading available lobbies...');
      _status = LobbyStatus.loading;
      notifyListeners();

      print('Fetching lobbies from PocketBase...');
      final response = await PocketBaseService.client
          .collection('lobbies')
          .getList(sort: '-created');

      print('Received ${response.items.length} lobbies from database');

      List<LobbyModel> lobbies = [];

      for (final item in response.items) {
        // For each lobby, fetch its participants
        print('Fetching participants for lobby ID: ${item.id}');
        final participantsResponse = await PocketBaseService.client
            .collection('lobby_participants')
            .getList(filter: 'lobby_id="${item.id}"');

        final participants = participantsResponse.items
            .map((participantRecord) => participantRecord.data['user_id'] as String)
            .toList();

        print('Found ${participants.length} participants for lobby ID: ${item.id}');

        lobbies.add(LobbyModel.fromPocketBase(item, participants: participants));
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

      // Create lobby in PocketBase
      final lobbyData = {
        'name': name,
        'host_id': hostId,
        'video_position': 0,
        'is_playing': false,
      };

      final record = await PocketBaseService.client
          .collection('lobbies')
          .create(body: lobbyData);

      // Add host as participant
      final participantData = {
        'lobby_id': record.id,
        'user_id': hostId,
      };

      await PocketBaseService.client
          .collection('lobby_participants')
          .create(body: participantData);

      // Create local model
      _currentLobby = LobbyModel.fromPocketBase(
        record,
        participants: [hostId],
      );

      _isHost = true;
      _status = LobbyStatus.ready;

      // Setup polling for real-time updates
      _setupLobbyRealTimeUpdates(record.id);

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
      final record = await PocketBaseService.client
          .collection('lobbies')
          .getOne(lobbyId);

      // Get participants
      final participantsResponse = await PocketBaseService.client
          .collection('lobby_participants')
          .getList(filter: 'lobby_id="$lobbyId"');

      final participants = participantsResponse.items
          .map((participantRecord) => participantRecord.data['user_id'] as String)
          .toList();

      // Check if user is host
      final lobby = LobbyModel.fromPocketBase(record, participants: participants);
      _isHost = lobby.hostId == userId;

      // Add user as participant if not already
      if (!participants.contains(userId)) {
        final participantData = {
          'lobby_id': lobbyId,
          'user_id': userId,
        };

        await PocketBaseService.client
            .collection('lobby_participants')
            .create(body: participantData);

        participants.add(userId);
      }

      _currentLobby = lobby.copyWith(participants: participants);

      // Setup polling
      _setupLobbyRealTimeUpdates(lobbyId);

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

      // Find and remove from participants table
      final participantsResponse = await PocketBaseService.client
          .collection('lobby_participants')
          .getList(
        filter: 'lobby_id="${_currentLobby!.id}" && user_id="$userId"',
      );

      if (participantsResponse.items.isNotEmpty) {
        final participantId = participantsResponse.items.first.id;
        await PocketBaseService.client
            .collection('lobby_participants')
            .delete(participantId);
      }

      // If host, delete lobby
      if (_isHost) {
        await PocketBaseService.client
            .collection('lobbies')
            .delete(_currentLobby!.id);
      }

      // Clean up resources
      _lobbySubscriptionTimer?.cancel();
      _participantsSubscriptionTimer?.cancel();
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
      final baseName = path.basename(videoFile.path);
      final fileName = '${_currentLobby!.id}_$baseName';
      final stopwatch = Stopwatch()..start();

      try {
        // Prepare form data for creating the record
        final formData = {
          'lobby_id': _currentLobby!.id,
          'filename': fileName,
        };

        // Use the PocketBase SDK to create a record with the file
        final record = await PocketBaseService.client
            .collection('videos')
            .create(
          body: formData,
          files: [
            await http.MultipartFile.fromPath('video', videoFile.path, filename: fileName),
          ],
        );

        // Get the video record ID
        final videoRecordId = record.id;

        // Extract the actual filename from the record data
        // The field name might be 'video', change it according to your schema
        final Map<String, dynamic> videoData = record.data;

        // This is the critical part - get the actual stored filename
        // The field name 'video' should be the name of the file field in your PocketBase collection
        final String actualFileName = videoData['video'];

        // Construct the proper URL manually
        final videoUrl = '${PocketBaseService.baseUrl}/api/files/videos/$videoRecordId/$actualFileName';

        // Update the lobby with the video URL
        await PocketBaseService.client
            .collection('lobbies')
            .update(_currentLobby!.id, body: {
          'video_url': videoUrl,
          'video_file_name': actualFileName,
        });

        // Update local state
        _currentLobby = _currentLobby!.copyWith(
          videoUrl: videoUrl,
          videoFileName: actualFileName,
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
        print('Downloading video from PocketBase');

        // Get the original video URL
        String videoUrl = _currentLobby!.videoUrl!;

        // Modify URL for Android emulator if needed
        if (Platform.isAndroid) {
          // Parse the original URL
          final uri = Uri.parse(videoUrl);

          // Check if it's a localhost URL
          if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
            // Create a new URL with 10.0.2.2 instead of localhost
            final newUri = Uri(
              scheme: uri.scheme,
              host: '10.0.2.2',
              port: uri.port,
              path: uri.path,
              query: uri.query,
              fragment: uri.fragment,
            );
            videoUrl = newUri.toString();
            print('Android detected, modified URL to: $videoUrl');
          }
        }

        if (Platform.isWindows) {
          // Parse the original URL
          final uri = Uri.parse(videoUrl);

          // Check if the URL is pointing to the Windows host (10.0.2.2)
          if (uri.host == '10.0.2.2') {
            // Create a new URL with localhost/127.0.0.1 instead
            final newUri = Uri(
              scheme: uri.scheme,
              host: '127.0.0.1',  // or 'localhost'
              port: uri.port,
              path: uri.path,
              query: uri.query,
              fragment: uri.fragment,
            );
            videoUrl = newUri.toString();
            print('Android detected, modified URL to: $videoUrl');
          }
        }

        // Try to get file size via HEAD request first
        int? totalSize;
        try {
          final headResponse = await http.head(Uri.parse(videoUrl));
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
        } catch (e) {
          print('Failed to get file size via HEAD: $e');
          // Continue without size
        }

        // Use an estimated size if not available
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
        final response = await http.get(Uri.parse(videoUrl));
        final bytes = response.bodyBytes;

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

      // In _initializeVideoPlayer method
      print('Video file path: $filePath');
      print('File exists: ${File(filePath).existsSync()}');
      print('File size: ${File(filePath).lengthSync()} bytes');

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

      // Get position after play command
      final newPosition = _videoController!.value.position.inMilliseconds;

      // Update the lobby state
      await PocketBaseService.client
          .collection('lobbies')
          .update(_currentLobby!.id, body: {
        'is_playing': true,
        'video_position': newPosition,
      });

      _currentLobby = _currentLobby!.copyWith(
        isPlaying: true,
        videoPosition: newPosition,
      );

      // Ensure synchronization after play attempt
      await ensureVideoSync();

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

      // Get position after pause
      final currentPosition = _videoController!.value.position.inMilliseconds;

      // Update the lobby state
      await PocketBaseService.client
          .collection('lobbies')
          .update(_currentLobby!.id, body: {
        'is_playing': false,
        'video_position': currentPosition,
      });

      _currentLobby = _currentLobby!.copyWith(
        isPlaying: false,
        videoPosition: currentPosition,
      );

      // Ensure synchronization after pause
      await ensureVideoSync();

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
      await PocketBaseService.client
          .collection('lobbies')
          .update(_currentLobby!.id, body: {
        'video_position': position.inMilliseconds,
      });

      _currentLobby = _currentLobby!.copyWith(
        videoPosition: position.inMilliseconds,
      );

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to seek video: ${e.toString()}';
      notifyListeners();
    }
  }

  // Setup polling for lobby updates (since PocketBase doesn't have built-in real-time subscriptions)
  void _setupLobbyRealTimeUpdates(String lobbyId) {
    _currentLobbyId = lobbyId;
    // Cancel any existing subscriptions
    _lobbySubscriptionTimer?.cancel();
    _participantsSubscriptionTimer?.cancel();

    // Subscribe to real-time changes on the lobby
    PocketBaseService.client.collection('lobbies').subscribe(lobbyId, (event) {
      // Now correctly handling RecordSubscriptionEvent
      if (event.action == 'update' || event.action == 'create') {
        final record = event.record; // This is already a RecordModel
        final updatedLobby = LobbyModel.fromPocketBase(record!);
        final previousLobby = _currentLobby;

        // Keep current participants
        final currentParticipants = _currentLobby?.participants ?? [];
        _currentLobby = updatedLobby.copyWith(participants: currentParticipants);

        // Handle video controller updates
        if (_videoController != null) {
          // Play/pause state changes
          if (previousLobby?.isPlaying != updatedLobby.isPlaying) {
            if (updatedLobby.isPlaying) {
              _videoController!.play();
            } else {
              _videoController!.pause();
            }
          }

          // Position changes for non-hosts
          if (!_isHost &&
              previousLobby?.videoPosition != updatedLobby.videoPosition &&
              (previousLobby?.videoPosition == null ||
                  (updatedLobby.videoPosition - previousLobby!.videoPosition).abs() > 500)) {
            _videoController!.seekTo(
              Duration(milliseconds: updatedLobby.videoPosition),
            );
          }
        }

        notifyListeners();
      }
    });

    // Poll for participants every 5 seconds
    _participantsSubscriptionTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      try {
        if (_currentLobby == null) return;

        final participantsResponse = await PocketBaseService.client
            .collection('lobby_participants')
            .getList(filter: 'lobby_id="$lobbyId"');

        final participants = participantsResponse.items
            .map((record) => record.data['user_id'] as String)
            .toList();

        _currentLobby = _currentLobby!.copyWith(participants: participants);
        notifyListeners();
      } catch (e) {
        print('Error polling participants: $e');
        // Don't update UI on polling errors
      }
    });
  }

  Future<void> ensureVideoSync() async {
    if (_videoController == null || _currentLobby == null) return;

    // Wait a short delay for player to stabilize
    await Future.delayed(Duration(milliseconds: 300));

    final isPlaying = _currentLobby!.isPlaying;
    final currentPosition = _videoController!.value.position.inMilliseconds;
    final expectedPosition = _currentLobby!.videoPosition;

    // Check if play state matches what's expected
    if (isPlaying != _videoController!.value.isPlaying) {
      print('Video play state out of sync. Expected: ${isPlaying ? 'playing' : 'paused'}, Actual: ${_videoController!.value.isPlaying ? 'playing' : 'paused'}');
      if (isPlaying) {
        await _videoController!.play();
      } else {
        await _videoController!.pause();
      }
    }

    // Check position synchronization (if difference > 500ms)
    if ((currentPosition - expectedPosition).abs() > 500) {
      print('Video position out of sync. Current: $currentPosition, Expected: $expectedPosition');
      await _videoController!.seekTo(Duration(milliseconds: expectedPosition));

      // If should be playing, ensure playback continues after seek
      if (isPlaying && !_videoController!.value.isPlaying) {
        await _videoController!.play();
      }
    }
  }
}