// screens/lobby_list_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/lobby_provider.dart';
import 'lobby_screen.dart';

class LobbyListScreen extends StatefulWidget {
  const LobbyListScreen({Key? key}) : super(key: key);

  @override
  _LobbyListScreenState createState() => _LobbyListScreenState();
}

class _LobbyListScreenState extends State<LobbyListScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lobbyNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load lobbies when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<LobbyProvider>(context, listen: false).loadAvailableLobbies();
    });
  }

  @override
  void dispose() {
    _lobbyNameController.dispose();
    super.dispose();
  }

  void _showCreateLobbyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Lobby'),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: _lobbyNameController,
              decoration: const InputDecoration(
                labelText: 'Lobby Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a lobby name';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
                  final lobbyProvider =
                  Provider.of<LobbyProvider>(context, listen: false);

                  final success = await lobbyProvider.createLobby(
                    name: _lobbyNameController.text.trim(),
                    hostId: authProvider.user!.id,
                  );

                  if (success && mounted) {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LobbyScreen(
                          lobbyId: lobbyProvider.currentLobby!.id,
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Lobbies'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<LobbyProvider>(context, listen: false)
                  .loadAvailableLobbies();
            },
          ),
        ],
      ),
      body: Consumer<LobbyProvider>(
        builder: (context, provider, _) {
          if (provider.status == LobbyStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.availableLobbies.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No active lobbies found',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _showCreateLobbyDialog,
                    child: const Text('Create New Lobby'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.availableLobbies.length,
            itemBuilder: (context, index) {
              final lobby = provider.availableLobbies[index];
              return ListTile(
                title: Text(lobby.name),
                subtitle: Text(
                    'Participants: ${lobby.participants.length}' +
                        (lobby.videoUrl != null ? ' • Video ready' : ' • No video yet')
                ),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LobbyScreen(
                        lobbyId: lobby.id,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateLobbyDialog,
        child: const Icon(Icons.add),
        tooltip: 'Create New Lobby',
      ),
    );
  }
}