# Pulse Group Chat Message Duplication & Live Sending Fix

## Issues Identified

### 1. Message Duplication
**Problem**: Messages were appearing multiple times in the chat feed.

**Root Cause**: The `_onSocketMessage` handler in `live_group_chat_page.dart` was not checking for duplicate messages before adding them to the message list. When the backend emits a message, it could sometimes be received multiple times due to:
- Socket reconnections
- Multiple listeners
- Race conditions in message delivery

**Fix Applied**: Added duplicate detection logic before adding messages:
```dart
// Prevent duplicate messages
final isDuplicate = _messages.any((m) => m.id == msg.id);
if (isDuplicate) {
  print('[LiveGroupChat] Duplicate message ignored: ${msg.id}');
  return;
}
```

### 2. Messages Not Sent Live
**Problem**: Messages were not appearing in real-time for other participants.

**Root Causes**:
1. Socket connection might be dropped without proper reconnection
2. No validation of socket connection state before sending messages
3. Timing issues with socket emission

**Fixes Applied**:
1. Added socket connection check before sending:
```dart
// Ensure socket is connected before sending
if (!SocketService.instance.isConnected) {
  print('[LiveGroupChat] Socket not connected, reconnecting...');
  await SocketService.instance.connect();
  await Future.delayed(const Duration(milliseconds: 500));
}
```

2. Added small delay after sending to ensure socket emits properly:
```dart
// Wait a bit for the socket to emit before scrolling
await Future.delayed(const Duration(milliseconds: 100));
```

### 3. Added Debug Logging
To help identify future issues, comprehensive logging was added:
- Socket message reception logging
- Message send operation logging
- Conversation ID tracking during bootstrap
- Connection state logging

## Files Modified

### `pulse/lib/pages/messaging/live_group_chat_page.dart`
1. **`_onSocketMessage` method**: Added duplicate detection and debug logging
2. **`_send` method**: Added socket connection validation and debug logging
3. **`_bootstrap` method**: Added conversation ID tracking logs

## Testing Recommendations

### 1. Test Message Duplication Fix
- [ ] Send multiple messages quickly in a row
- [ ] Check that each message appears only once
- [ ] Test with poor network conditions
- [ ] Test reconnecting to chat after backgrounding app

### 2. Test Live Message Sending
- [ ] Send message from Device A, verify it appears on Device B in real-time
- [ ] Test with app backgrounded and then foregrounded
- [ ] Test with socket disconnected (airplane mode on/off)
- [ ] Send messages with images and videos

### 3. Test Conversation Synchronization
- [ ] Join pulse group chat from multiple devices
- [ ] Verify all devices show the same conversation ID
- [ ] Check console logs for conversation ID mismatches

## Backend Considerations

The backend socket handling in `backend/src/index.ts` already includes:
- Message deduplication logic (3-second window)
- Proper room joining via `join:conversation` event
- Message emission to all room participants via `io.to(\`conversation:${conversationId}\`).emit('message:new', ...)`

## Additional Notes

### Socket Connection Management
The fix ensures that:
1. Socket connection is validated before each send operation
2. Automatic reconnection occurs if socket is disconnected
3. Messages are properly queued if socket is temporarily unavailable (via `_emitOrQueue` in SocketService)

### Conversation ID Normalization
The bootstrap process handles cases where:
- Pulse ID is passed instead of conversation ID
- Multiple conversation IDs exist for the same pulse
- Backend returns a canonical conversation ID different from the initial one

## Future Improvements

Consider implementing:
1. **Optimistic UI updates**: Show messages immediately before socket confirmation
2. **Message retry logic**: Automatically retry failed messages
3. **Better offline handling**: Queue messages when offline and send when online
4. **Message status indicators**: Show sent/delivered/read status per message
5. **Remove debug logs**: Once confirmed working, remove console.log statements from production

## Rollback Plan

If issues persist, revert changes to:
```bash
git checkout HEAD -- pulse/lib/pages/messaging/live_group_chat_page.dart
```

## Monitoring

Watch for these console log patterns:
- `[LiveGroupChat] Duplicate message ignored:` - Should be rare
- `[LiveGroupChat] Socket not connected, reconnecting...` - Monitor frequency
- `[LiveGroupChat] Message ignored - wrong conversation` - Investigate if frequent
- `[LiveGroupChat] Error processing socket message:` - Critical errors
