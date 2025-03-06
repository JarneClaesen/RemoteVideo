// lib/screens/lobby_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/file_transfer_progress.dart';
import '../providers/auth_provider.dart';
import '../providers/lobby_provider.dart';

class LobbyScreen extends StatefulWidget {
  final String lobbyId;

  const LobbyScreen({
    Key? key,
    required this.lobbyId,
  }) : super(key: key);

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

// Complete implementation of the LobbyScreen class
class _LobbyScreenState extends State<LobbyScreen> {
  late final LobbyProvider _lobbyProvider;
  late final AuthProvider _authProvider;
  File? _selectedVideo;
  bool _isVideoControlsVisible = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _lobbyProvider = Provider.of<LobbyProvider>(context, listen: false);
    _authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Join the lobby when the screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lobbyProvider.joinLobby(
        lobbyId: widget.lobbyId,
        userId: _authProvider.user!.id,
      );
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _lobbyProvider.leaveLobby(_authProvider.user!.id);
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final pickedFile = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedVideo = File(pickedFile.path);
        });

        await _lobbyProvider.uploadVideo(_selectedVideo!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick video: $e')),
      );
    }
  }

  void _toggleControls() {
    setState(() {
      _isVideoControlsVisible = !_isVideoControlsVisible;
    });

    _resetHideControlsTimer();
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isVideoControlsVisible) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isVideoControlsVisible = false;
          });
        }
      });
    }
  }

  void _showParticipantsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer<LobbyProvider>(
          builder: (context, provider, _) {
            final participants = provider.currentLobby?.participants ?? [];
            return AlertDialog(
              title: const Text('Participants'),
              content: SizedBox(
                width: double.maxFinite,
                child: participants.isEmpty
                    ? const Center(child: Text('No participants yet'))
                    : ListView.builder(
                  shrinkWrap: true,
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    final participantId = participants[index];
                    final isHost = provider.currentLobby?.hostId == participantId;
                    return ListTile(
                      title: Text('Participant ${index + 1}'),
                      trailing: isHost
                          ? const Chip(label: Text('Host'))
                          : null,
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _lobbyProvider.leaveLobby(_authProvider.user!.id);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Consumer<LobbyProvider>(
            builder: (context, provider, _) {
              return Text(provider.currentLobby?.name ?? 'Loading...');
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () {
                _showParticipantsDialog();
              },
            ),
          ],
        ),
        body: Consumer<LobbyProvider>(
          builder: (context, provider, _) {
            // Show progress indicators for uploading/downloading
            if (provider.status == LobbyStatus.videoUploading ||
                provider.status == LobbyStatus.videoDownloading) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildTransferProgress(provider),
                ),
              );
            }

            switch (provider.status) {
              case LobbyStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case LobbyStatus.error:
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error: ${provider.errorMessage}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          provider.joinLobby(
                            lobbyId: widget.lobbyId,
                            userId: _authProvider.user!.id,
                          );
                        },
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                );
              case LobbyStatus.initial:
              case LobbyStatus.ready:
              case LobbyStatus.videoReady:
                return Column(
                  children: [
                    Expanded(
                      child: _buildVideoPlayer(provider),
                    ),
                    _buildBottomControls(provider),
                  ],
                );
              default:
                return const Center(child: Text('Unknown state'));
            }
          },
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(LobbyProvider provider) {
    if (provider.videoController != null &&
        provider.videoController!.value.isInitialized) {
      return GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: provider.videoController!.value.aspectRatio,
              child: VideoPlayer(provider.videoController!),
            ),
            if (_isVideoControlsVisible)
              Container(
                color: Colors.black26,
                child: _buildVideoControls(provider),
              ),
          ],
        ),
      );
    } else if (provider.status == LobbyStatus.ready) {
      if (provider.isHost) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'You are the host of this lobby.',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              const Text('Upload a video to get started:'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Video'),
                onPressed: _pickVideo,
              ),
            ],
          ),
        );
      } else {
        return const Center(
          child: Text(
            'Waiting for the host to upload a video...',
            style: TextStyle(fontSize: 18),
          ),
        );
      }
    } else {
      // Show specific loading states
      String loadingMessage = 'Loading...';
      if (provider.status == LobbyStatus.videoUploading) {
        loadingMessage = 'Uploading video...';
      } else if (provider.status == LobbyStatus.videoDownloading) {
        loadingMessage = 'Downloading video...';
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(loadingMessage),
            if (provider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
    }
  }

  Widget _buildTransferProgress(LobbyProvider provider) {
    // Show upload progress
    if (provider.status == LobbyStatus.videoUploading && provider.uploadProgress != null) {
      return _buildProgressIndicator(
        provider.uploadProgress!,
        'Uploading video...',
      );
    }

    // Show download progress
    if (provider.status == LobbyStatus.videoDownloading && provider.downloadProgress != null) {
      return _buildProgressIndicator(
        provider.downloadProgress!,
        'Downloading video...',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildProgressIndicator(FileTransferProgress progress, String title) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.totalBytes != null ? progress.progress : null,
            minHeight: 10,
            borderRadius: BorderRadius.circular(3),
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.formattedTransferred} / ${progress.formattedTotal}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                progress.formattedSpeed,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (progress.totalBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '${progress.formattedProgress} complete',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoControls(LobbyProvider provider) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top controls - title
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            provider.currentLobby?.videoFileName ?? 'Video',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Middle - play/pause button
        IconButton(
          icon: Icon(
            provider.videoController!.value.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            size: 60,
          ),
          onPressed: provider.isHost
              ? () {
            if (provider.videoController!.value.isPlaying) {
              provider.pauseVideo();
            } else {
              provider.playVideo();
            }
            _resetHideControlsTimer();
          }
              : null, // Non-hosts can't control playback
        ),
        // Bottom controls - progress bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Text(
                _formatDuration(provider.videoController!.value.position),
              ),
              Expanded(
                child: Slider(
                  value: provider.videoController!.value.position.inMilliseconds
                      .toDouble(),
                  min: 0.0,
                  max: provider.videoController!.value.duration.inMilliseconds
                      .toDouble(),
                  onChanged: provider.isHost
                      ? (value) {
                    final newPosition =
                    Duration(milliseconds: value.toInt());
                    provider.videoController!.seekTo(newPosition);
                    _resetHideControlsTimer();
                  }
                      : null, // Non-hosts can't seek
                  onChangeEnd: provider.isHost
                      ? (value) {
                    final newPosition =
                    Duration(milliseconds: value.toInt());
                    provider.seekVideo(newPosition);
                    _resetHideControlsTimer();
                  }
                      : null, // Non-hosts can't seek
                ),
              ),
              Text(
                _formatDuration(provider.videoController!.value.duration),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls(LobbyProvider provider) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceDim,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (provider.isHost && provider.status == LobbyStatus.videoReady)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Upload new video',
              onPressed: _pickVideo,
            ),
          Text(
            'Participants: ${provider.currentLobby?.participants.length ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Leave lobby',
            onPressed: () async {
              await provider.leaveLobby(_authProvider.user!.id);
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours == '00' ? '$minutes:$seconds' : '$hours:$minutes:$seconds';
  }
}
