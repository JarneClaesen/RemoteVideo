class LobbyModel {
  final String id;
  final String name;
  final String hostId;
  final String? videoUrl;
  final String? videoFileName;
  final int videoPosition; // renamed from currentPosition
  final bool isPlaying;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> participants; // Will be populated separately

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

  factory LobbyModel.fromJson(Map<String, dynamic> json) {
    return LobbyModel(
      id: json['id'],
      name: json['name'],
      hostId: json['host_id'],
      videoUrl: json['video_url'],
      videoFileName: json['video_file_name'],
      videoPosition: json['video_position'] ?? 0,
      isPlaying: json['is_playing'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      participants: json['participants'] != null
          ? List<String>.from(json['participants'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host_id': hostId,
      'video_url': videoUrl,
      'video_file_name': videoFileName,
      'video_position': videoPosition,
      'is_playing': isPlaying,
      // Don't include timestamps or participants when inserting
    };
  }

  // Update copyWith method to match new fields
  LobbyModel copyWith({
    String? id,
    String? name,
    String? hostId,
    String? videoUrl,
    String? videoFileName,
    int? videoPosition,
    bool? isPlaying,
    DateTime? createdAt,
    DateTime? updatedAt,
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