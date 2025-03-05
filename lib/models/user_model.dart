// lib/models/user_model.dart
class UserModel {
  final String id;
  final String email;
  final String? username;
  final bool isHost;

  UserModel({
    required this.id,
    required this.email,
    this.username,
    this.isHost = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      username: json['username'],
      isHost: json['is_host'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'is_host': isHost,
    };
  }
}