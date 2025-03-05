import 'package:pocketbase/pocketbase.dart';

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

  factory UserModel.fromPocketBase(RecordModel record) {
    return UserModel(
      id: record.id,
      email: record.data['email'] ?? '',
      username: record.data['username'],
      isHost: record.data['is_host'] ?? false,
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