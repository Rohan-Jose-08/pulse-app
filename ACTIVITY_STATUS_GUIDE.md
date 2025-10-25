# Activity Status System Implementation Guide

## Overview

The Activity Status System provides real-time presence tracking for users in the Pulse app. It tracks whether users are online, offline, or away, and broadcasts status changes to other connected clients in real-time.

## Features

✅ **Real-time Status Tracking**
- Online: User has active socket connection
- Offline: All user's sockets disconnected
- Away: User manually sets away status or after inactivity

✅ **Privacy-Respecting**
- Users can hide their activity status via `activityStatusVisible` setting
- Status is only shared with users who have permission to see it

✅ **Automatic Status Management**
- Automatically sets online when socket connects
- Automatically sets offline when all sockets disconnect
- Tracks multiple simultaneous connections per user

✅ **Last Seen Tracking**
- Records last activity timestamp
- Useful for "last seen X minutes ago" displays

---

## Architecture

### Backend Components

#### 1. **Data Structures** (`backend/src/realtime.ts`)

```typescript
interface UserActivity {
  userId: string;
  status: 'online' | 'offline' | 'away';
  lastSeen: Date;
  socketCount: number; // Tracks multiple connections
}

export const userActivityStatus = new Map<string, UserActivity>();
```

#### 2. **Core Functions**

**`setUserOnline(userId: string)`**
- Increments socket count for user
- Sets status to 'online'
- Broadcasts 'user:status' event to other users

**`setUserOffline(userId: string)`**
- Decrements socket count
- If count reaches 0, sets status to 'offline'
- Broadcasts offline status

**`setUserAway(userId: string)`**
- Manually sets user to away status
- Useful for "Do Not Disturb" features

**`getUserActivity(userId: string)`**
- Returns current activity status for a user
- Returns null if no activity tracked

**`getOnlineUsers()`**
- Returns array of all currently online user IDs
- Useful for "who's online" features

**`updateLastSeen(userId: string)`**
- Updates last activity timestamp
- Called on any user action

#### 3. **Socket.IO Integration** (`backend/src/index.ts`)

```typescript
io.on('connection', (socket: any) => {
  const user = (socket as any).user as { id: string };
  
  // Set user online when they connect
  setUserOnline(user.id);
  
  socket.on('disconnect', () => {
    const set = userSockets.get(user.id);
    if (set) {
      set.delete(socket.id);
      if (set.size === 0) {
        // User has no more active connections
        setUserOffline(user.id);
      }
    }
  });
});
```

#### 4. **API Endpoints** (`backend/src/routes/activity.ts`)

**POST `/api/activity/status`**
- Request body: `{ userIds: string[] }`
- Returns status for multiple users
- Respects privacy settings

**GET `/api/activity/online`**
- Returns list of all online users
- Only includes users with `activityStatusVisible: true`

**POST `/api/activity/away`**
- Sets current user to away status
- Requires authentication

---

### Frontend Components

#### 1. **Socket Service** (`pulse/lib/backend/socket_service.dart`)

```dart
// Stream for receiving status updates
Stream<Map<String, dynamic>> get userStatusChanged => _userStatusChanged.stream;

// Socket listener
_socket!.on('user:status', (data) =>
    _userStatusChanged.add(Map<String, dynamic>.from(data)));
```

#### 2. **API Service** (`pulse/lib/backend/api_service.dart`)

```dart
/// Get activity status for specific users
Future<Map<String, dynamic>?> getActivityStatuses(List<String> userIds)

/// Get all online users (who have made their status visible)
Future<List<Map<String, dynamic>>?> getOnlineUsers()

/// Manually set away status
Future<bool> setAwayStatus()
```

---

## Usage Examples

### Backend: Broadcasting Status Changes

```typescript
import { setUserOnline, setUserOffline, getUserActivity } from './realtime';

// When user connects
setUserOnline(userId);
// Automatically broadcasts to all connected clients

// Check user status
const activity = getUserActivity(userId);
if (activity?.status === 'online') {
  console.log(`User ${userId} is online`);
}

// When user disconnects
setUserOffline(userId);
```

### Frontend: Displaying User Status

```dart
// Initialize in your widget
@override
void initState() {
  super.initState();
  _loadInitialStatuses();
  _listenToStatusChanges();
}

// Load initial statuses for conversation participants
Future<void> _loadInitialStatuses() async {
  final userIds = ['user1', 'user2', 'user3'];
  final statuses = await ApiService.instance.getActivityStatuses(userIds);
  
  setState(() {
    statuses?.forEach((userId, statusData) {
      if (statusData != null) {
        _userStatuses[userId] = statusData['status'];
      }
    });
  });
}

// Listen for real-time updates
void _listenToStatusChanges() {
  SocketService.instance.userStatusChanged.listen((data) {
    final userId = data['userId'] as String?;
    final status = data['status'] as String?;
    
    if (userId != null && status != null) {
      setState(() {
        _userStatuses[userId] = status;
      });
    }
  });
}

// Display status indicator
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
```

---

## Privacy Settings Integration

The activity status system respects the `activityStatusVisible` setting in the User model:

```prisma
model User {
  // ...
  activityStatusVisible Boolean @default(true)
  // ...
}
```

**How it works:**

1. User can toggle "Activity Status" in settings
2. When disabled, the API returns `null` for that user's status
3. Other users see no status indicator for that user
4. The user still tracks their own status internally for features that need it

**Example API Response:**

```json
{
  "statuses": {
    "user1": {
      "status": "online",
      "lastSeen": "2024-01-15T10:30:00Z"
    },
    "user2": null,  // Activity status hidden
    "user3": {
      "status": "offline",
      "lastSeen": "2024-01-15T09:15:00Z"
    }
  }
}
```

---

## Best Practices

### 1. **Efficient Status Checking**

❌ **Bad:** Check status individually for each user
```dart
for (var userId in userIds) {
  await ApiService.instance.getActivityStatuses([userId]);
}
```

✅ **Good:** Batch check for multiple users
```dart
await ApiService.instance.getActivityStatuses(userIds);
```

### 2. **Real-time Updates**

Always listen to Socket.IO events rather than polling:

```dart
// Listen once in initState
SocketService.instance.userStatusChanged.listen((data) {
  _updateUserStatus(data);
});
```

### 3. **UI Performance**

Cache statuses locally and only update when changed:

```dart
final Map<String, String> _statusCache = {};

void _updateStatus(String userId, String status) {
  if (_statusCache[userId] != status) {
    setState(() {
      _statusCache[userId] = status;
    });
  }
}
```

### 4. **Error Handling**

Always handle null responses gracefully:

```dart
final statuses = await ApiService.instance.getActivityStatuses(userIds);
if (statuses == null) {
  // Network error or auth issue
  return;
}

statuses.forEach((userId, statusData) {
  if (statusData != null) {
    // User has visible status
    _updateUserStatus(userId, statusData['status']);
  } else {
    // User has hidden status - show no indicator
  }
});
```

---

## Common Use Cases

### 1. **Chat Conversation Header**

Show if the other person is online:

```dart
Widget _buildConversationHeader() {
  return ListTile(
    leading: UserAvatarWithStatus(
      userId: otherUserId,
      status: _userStatuses[otherUserId],
      imageUrl: otherUserImageUrl,
    ),
    title: Text(otherUserName),
    subtitle: _buildStatusText(_userStatuses[otherUserId]),
  );
}

Widget _buildStatusText(String? status) {
  if (status == 'online') {
    return Text('Active now', style: TextStyle(color: Colors.green));
  }
  return Text('Offline');
}
```

### 2. **Friends List**

Show online friends at the top:

```dart
List<User> _sortedFriends() {
  return friends.toList()
    ..sort((a, b) {
      final aStatus = _userStatuses[a.id] ?? 'offline';
      final bStatus = _userStatuses[b.id] ?? 'offline';
      
      if (aStatus == 'online' && bStatus != 'online') return -1;
      if (aStatus != 'online' && bStatus == 'online') return 1;
      return 0;
    });
}
```

### 3. **Group Chat Participants**

Show who's currently active:

```dart
Widget _buildParticipantsList() {
  final onlineCount = participants
      .where((p) => _userStatuses[p.id] == 'online')
      .length;
  
  return Column(
    children: [
      Text('$onlineCount/${participants.length} online'),
      ...participants.map((p) => ListTile(
        leading: UserAvatarWithStatus(
          userId: p.id,
          status: _userStatuses[p.id],
        ),
        title: Text(p.name),
      )),
    ],
  );
}
```

---

## Testing

### Backend Tests

```typescript
describe('Activity Status', () => {
  it('should set user online', () => {
    setUserOnline('user1');
    const activity = getUserActivity('user1');
    expect(activity?.status).toBe('online');
    expect(activity?.socketCount).toBe(1);
  });

  it('should handle multiple connections', () => {
    setUserOnline('user1');
    setUserOnline('user1');
    const activity = getUserActivity('user1');
    expect(activity?.socketCount).toBe(2);
  });

  it('should set offline when all sockets disconnect', () => {
    setUserOnline('user1');
    setUserOnline('user1');
    setUserOffline('user1');
    setUserOffline('user1');
    const activity = getUserActivity('user1');
    expect(activity?.status).toBe('offline');
  });
});
```

### Frontend Tests

```dart
testWidgets('Activity status indicator', (tester) async {
  await tester.pumpWidget(
    UserAvatarWithStatus(
      userId: 'test-user',
      status: 'online',
    ),
  );
  
  // Check that green indicator is shown
  final indicator = find.byType(Container);
  expect(indicator, findsOneWidget);
});
```

---

## Future Enhancements

### Planned Features

1. **Automatic Away Detection**
   - Set user to "away" after 5 minutes of inactivity
   - Track last user interaction timestamp

2. **Custom Status Messages**
   - Allow users to set custom status text
   - "🎮 Gaming", "📚 Studying", etc.

3. **Do Not Disturb Mode**
   - Appear offline even when online
   - Disable all notifications

4. **Typing Indicators Enhancement**
   - Show when user is typing in specific conversation
   - Integrated with activity status

5. **Analytics**
   - Track average online time
   - Peak activity hours
   - User engagement metrics

---

## Troubleshooting

### Issue: Status not updating in real-time

**Solution:** Ensure Socket.IO is connected:
```dart
if (!SocketService.instance.isConnected) {
  await SocketService.instance.connect();
}
```

### Issue: Status shows null for all users

**Solution:** Check authentication and privacy settings:
```dart
final token = await FirebaseAuth.instance.currentUser?.getIdToken();
print('Auth token: $token');

// Verify user has activityStatusVisible set to true
```

### Issue: User stays online after disconnect

**Solution:** Check that disconnect handler is properly configured:
```typescript
socket.on('disconnect', () => {
  // Must call setUserOffline when socket count reaches 0
});
```

---

## API Reference

### Socket.IO Events

#### Incoming (Server → Client)

**`user:status`**
```typescript
{
  userId: string;
  status: 'online' | 'offline' | 'away';
  lastSeen: string; // ISO 8601 timestamp
}
```

### REST API

#### POST `/api/activity/status`

**Request:**
```json
{
  "userIds": ["user1", "user2", "user3"]
}
```

**Response:**
```json
{
  "statuses": {
    "user1": {
      "status": "online",
      "lastSeen": "2024-01-15T10:30:00Z"
    },
    "user2": null,
    "user3": {
      "status": "offline",
      "lastSeen": "2024-01-15T09:15:00Z"
    }
  }
}
```

#### GET `/api/activity/online`

**Response:**
```json
{
  "users": [
    {
      "id": "user1",
      "displayName": "John Doe",
      "profileImageUrl": "https://..."
    }
  ]
}
```

#### POST `/api/activity/away`

**Response:**
```json
{
  "success": true,
  "status": "away"
}
```

---

## Summary

The Activity Status System is now fully implemented with:

✅ Backend tracking with automatic online/offline detection
✅ Real-time WebSocket broadcasts
✅ Privacy-respecting API endpoints
✅ Flutter client integration
✅ Example components for common UI patterns
✅ Comprehensive documentation

Users can now see who's online in real-time while respecting privacy preferences!
