# Discord-Style Group Call Status Bar - Fix Summary

## Issues Fixed

### 1. ✅ Call Status Bar Disappears When Returning to Chat
**Problem**: The call status bar would disappear when exiting and re-entering the chat page.

**Solution**: 
- Added `groupcall:status` event that backend emits when a user joins a conversation room
- Backend now sends active call information immediately when you join a conversation
- Frontend listens for this event and restores the call state
- Call state is now properly persisted as long as the call is active

**Backend Changes** (`backend/src/index.ts`):
```typescript
socket.on('join:conversation', (conversationId: string) => {
  socket.join(`conversation:${conversationId}`);
  
  // Send active call status if there's an ongoing call
  const members = activeGroupCalls.get(conversationId);
  if (members && members.size > 0) {
    const meta = groupCallMeta.get(conversationId);
    const participants = Array.from(members);
    socket.emit('groupcall:status', {
      conversationId,
      isActive: true,
      isVideo: meta?.isVideo ?? true,
      participants,
    });
  }
});
```

**Frontend Changes**:
- Added `groupCallStatus` stream to `SocketService`
- Added listener in `LiveGroupChatPage` to restore call state
- State restoration happens automatically when entering chat

### 2. ✅ Removed Bottom Snackbar Notification
**Problem**: Annoying snackbar appeared at the bottom when a call started.

**Solution**: 
- Removed `CustomSnackbar.showInfo()` call
- Kept haptic feedback for tactile response
- The prominent status bar is sufficient visual feedback

**Before**:
```dart
CustomSnackbar.showInfo(
  context,
  message: isVideo ? 'Video call started' : 'Voice call started',
);
```

**After**:
```dart
// Light haptic feedback only
await HapticUtils.light();
```

## Files Modified

### Backend
1. **`backend/src/index.ts`**
   - Modified `join:conversation` socket handler
   - Sends `groupcall:status` event with active call info

### Frontend
1. **`pulse/lib/backend/socket_service.dart`**
   - Added `_gcStatus` stream controller
   - Added `groupCallStatus` getter
   - Added listener for `groupcall:status` event

2. **`pulse/lib/pages/messaging/live_group_chat_page.dart`**
   - Added listener for `groupCallStatus` stream
   - Restores call state when receiving status
   - Removed snackbar notification
   - Kept haptic feedback

## How It Works Now

### Flow When Entering a Chat with Active Call:

1. User opens chat page
2. `SocketService.instance.joinConversation(_chatId)` is called
3. Backend receives `join:conversation` event
4. Backend checks if there's an active call for this conversation
5. If active call exists, backend emits `groupcall:status` event
6. Frontend receives status and updates state:
   - Sets `_isCallActive = true`
   - Sets `_isCallVideo` to correct type
   - Sets participant list and count
7. Status bar appears automatically with correct information

### What Happens When Call Starts:

1. Someone starts a call
2. Backend broadcasts `groupcall:started` event
3. Frontend updates state to show status bar
4. Haptic feedback provides subtle notification
5. No intrusive snackbar

## Testing Instructions

1. **Test Persistence**:
   - User A starts a video call in a pulse group
   - User B opens the chat (should see status bar immediately)
   - User B exits and re-enters chat (status bar should persist)
   - User B joins the call
   - User C opens the chat (should see 2 people in call)

2. **Test No Snackbar**:
   - Start a call
   - Verify no snackbar appears at bottom
   - Status bar at top should be only visual indicator
   - Should feel haptic feedback (if device supports it)

3. **Test Real-Time Updates**:
   - Multiple users join/leave call
   - Participant count should update in real-time
   - Status bar should appear/disappear correctly

## Benefits

✨ **Better UX**: Call status persists when navigating
🎯 **Less Intrusive**: No snackbar blocking content  
📱 **Discord-Like**: Matches familiar UX pattern
⚡ **Real-Time**: Participant count updates live
🔄 **Reliable**: State restoration on page entry
