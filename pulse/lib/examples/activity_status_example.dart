/// Example usage of Activity Status System
///
/// This demonstrates how to:
/// 1. Check if a user is online/away/offline
/// 2. Listen for real-time status changes
/// 3. Display status indicators in the UI
/// 4. Respect user privacy settings

import 'package:flutter/material.dart';
import '../backend/socket_service.dart';
import '../backend/api_service.dart';

class ActivityStatusExample extends StatefulWidget {
  const ActivityStatusExample({Key? key}) : super(key: key);

  @override
  State<ActivityStatusExample> createState() => _ActivityStatusExampleState();
}

class _ActivityStatusExampleState extends State<ActivityStatusExample> {
  final Map<String, String> _userStatuses = {}; // userId -> status
  final Map<String, DateTime> _lastSeenTimes = {}; // userId -> lastSeen

  @override
  void initState() {
    super.initState();
    _loadOnlineUsers();
    _listenToStatusChanges();
  }

  /// Load initial list of online users
  Future<void> _loadOnlineUsers() async {
    final onlineUsers = await ApiService.instance.getOnlineUsers();
    if (onlineUsers != null) {
      setState(() {
        for (var user in onlineUsers) {
          _userStatuses[user['id']] = 'online';
        }
      });
    }
  }

  /// Listen for real-time status updates via Socket.IO
  void _listenToStatusChanges() {
    SocketService.instance.userStatusChanged.listen((data) {
      final userId = data['userId'] as String?;
      final status = data['status'] as String?;
      final lastSeenStr = data['lastSeen'] as String?;

      if (userId != null && status != null) {
        setState(() {
          _userStatuses[userId] = status;
          if (lastSeenStr != null) {
            _lastSeenTimes[userId] = DateTime.parse(lastSeenStr);
          }
        });
      }
    });
  }

  /// Get activity status for specific users
  Future<void> _checkSpecificUsers(List<String> userIds) async {
    final statuses = await ApiService.instance.getActivityStatuses(userIds);
    if (statuses != null) {
      setState(() {
        statuses.forEach((userId, statusData) {
          if (statusData != null) {
            _userStatuses[userId] = statusData['status'];
            final lastSeenStr = statusData['lastSeen'];
            if (lastSeenStr != null) {
              _lastSeenTimes[userId] = DateTime.parse(lastSeenStr);
            }
          }
        });
      });
    }
  }

  /// Build a status indicator widget
  Widget _buildStatusIndicator(String status) {
    Color color;
    switch (status) {
      case 'online':
        color = Colors.green;
        break;
      case 'away':
        color = Colors.orange;
        break;
      case 'offline':
      default:
        color = Colors.grey;
        break;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  /// Format last seen time
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Status Example'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Online Users',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_userStatuses.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No online users'),
              ),
            )
          else
            ..._userStatuses.entries.map((entry) {
              final userId = entry.key;
              final status = entry.value;
              final lastSeen = _lastSeenTimes[userId];

              return ListTile(
                leading: Stack(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _buildStatusIndicator(status),
                    ),
                  ],
                ),
                title: Text('User $userId'),
                subtitle: Text(
                  status == 'online'
                      ? 'Active now'
                      : lastSeen != null
                          ? 'Last seen ${_formatLastSeen(lastSeen)}'
                          : status,
                ),
                trailing: Chip(
                  label: Text(status.toUpperCase()),
                  backgroundColor: status == 'online'
                      ? Colors.green.withOpacity(0.2)
                      : status == 'away'
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                ),
              );
            }).toList(),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _loadOnlineUsers,
            child: const Text('Refresh Online Users'),
          ),
        ],
      ),
    );
  }
}

/// Example: User Avatar with Status Indicator
/// Use this widget to show user status in any list or chat interface
class UserAvatarWithStatus extends StatelessWidget {
  final String userId;
  final String? status;
  final String? imageUrl;
  final double size;

  const UserAvatarWithStatus({
    Key? key,
    required this.userId,
    this.status,
    this.imageUrl,
    this.size = 48,
  }) : super(key: key);

  Color _getStatusColor() {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'offline':
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
          child: imageUrl == null ? const Icon(Icons.person) : null,
        ),
        if (status != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: _getStatusColor(),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
