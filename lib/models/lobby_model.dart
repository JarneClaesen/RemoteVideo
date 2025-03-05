import 'package:pocketbase/pocketbase.dart';

class LobbyModel {
  final String id;
  final String name;
  final String hostId;
  final String? videoUrl;
  final String? videoFileName;
  final int videoPosition;
  final bool isPlaying;
  final String createdAt;
  final String updatedAt;
  final List<String> participants;

  LobbyModel({
    required this.id,
    required this.name,
    required this.hostId,
    this.videoUrl,
    this.videoFileName,
    this.videoPosition = 0,
    this.isPlaying = false,
    required this.createdAt,
    required this.updatedAt,
    this.participants = const [],
  });

  factory LobbyModel.fromPocketBase(RecordModel record, {List<String> participants = const []}) {
    return LobbyModel(
      id: record.id,
      name: record.data['name'] ?? '',
      hostId: record.data['host_id'] ?? '',
      videoUrl: record.data['video_url'],
      videoFileName: record.data['video_file_name'],
      videoPosition: record.data['video_position'] ?? 0,
      isPlaying: record.data['is_playing'] ?? false,
      createdAt: record.created,
      updatedAt: record.updated,
      participants: participants,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host_id': hostId,
      'video_url': videoUrl,
      'video_file_name': videoFileName,
      'video_position': videoPosition,
      'is_playing': isPlaying,
    };
  }

  LobbyModel copyWith({
    String? id,
    String? name,
    String? hostId,
    String? videoUrl,
    String? videoFileName,
    int? videoPosition,
    bool? isPlaying,
    String? createdAt,
    String? updatedAt,
    List<String>? participants,
  }) {
    return LobbyModel(
      id: id ?? this.id,
      name: name ?? this.name,
      hostId: hostId ?? this.hostId,
      videoUrl: videoUrl ?? this.videoUrl,
      videoFileName: videoFileName ?? this.videoFileName,
      videoPosition: videoPosition ?? this.videoPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participants: participants ?? this.participants,
    );
  }
}