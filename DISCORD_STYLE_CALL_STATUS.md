# Discord-Style Group Call Status Implementation

## Overview

Implemented Discord-style active call indicators and status bars for pulse group chats and regular group chats. Users can now see when a call is active and join with a single tap, similar to Discord's voice channel UI.

## Features Implemented

### 1. **Active Call Status Bar in Chat**
When a group call is active in a conversation, a prominent status bar appears at the top of the chat:

**Features:**
- 🎨 **Visual Design**: Gradient background (purple for video, green for voice)
- 💫 **Animated Indicator**: Pulsing circle icon that draws attention
- 👥 **Participant Count**: Shows how many people are in the call
- 🎯 **One-Tap Join**: Tap anywhere on the bar to join the call
- ✨ **Smooth Animation**: Slides down from top when call starts
- 📱 **Permission Handling**: Automatically requests mic/camera permissions

**Location:** Between top bar and chat messages

### 2. **Enhanced Messaging Hub Call Indicators**
The messaging hub now shows rich call status for conversations with active calls:

**Features:**
- 🟢 **Status Badge**: Colored badge showing call type (video/voice)
- 📊 **Participant Count**: Shows number of people in call
- 💬 **Call to Action**: "Tap to join" hint text
- 🎨 **Color Coding**: 
  - Purple for video calls
  - Green for voice calls
- 📍 **Badge Position**: Shows prominently in conversation subtitle

### 3. **Real-Time Call State Tracking**
Automatically tracks and updates call status:

**Tracked Information:**
- Whether a call is active
- Call type (video or voice)
- Number of participants
- List of participant IDs
- Join/leave events in real-time

**Socket Events Monitored:**
- `groupcall:started` - Call begins
- `groupcall:stopped` - Call ends
- `groupcall:participants` - Initial participant list
- `groupcall:participant-joined` - Someone joins
- `groupcall:participant-left` - Someone leaves

## Files Modified

### `pulse/lib/pages/messaging/live_group_chat_page.dart`

#### State Variables Added:
```dart
// Active call state
bool _isCallActive = false;
bool _isCallVideo = true;
int _callParticipantCount = 0;
List<String> _callParticipants = [];

// Socket subscriptions
StreamSubscription<Map<String, dynamic>>? _gcStartedSub;
StreamSubscription<Map<String, dynamic>>? _gcStoppedSub;
StreamSubscription<Map<String, dynamic>>? _gcParticipantsSub;
StreamSubscription<Map<String, dynamic>>? _gcParticipantJoinedSub;
StreamSubscription<Map<String, dynamic>>? _gcParticipantLeftSub;
```

#### New Method: `_callStatusBar()`
Creates the Discord-style status bar with:
- Animated pulsing indicator
- Call type and participant info
- Tap-to-join functionality
- Permission requests
- Navigation to call screen

#### Updated `_setupSocketListeners()`
Added comprehensive call event listeners:
- Tracks call start/stop
- Updates participant count in real-time
- Manages call active state
- Shows haptic feedback

#### Updated `dispose()`
Properly cancels all group call subscriptions to prevent memory leaks.

### `pulse/lib/pages/messaging/messages_hub_widget.dart`

#### Enhanced Subtitle in Pulse Conversations:
Added active call status badge showing:
- Call type icon
- Participant count
- "Tap to join" hint
- Color-coded by call type

#### Enhanced Subtitle in Group Chats:
Same active call status badge for regular group chats.

## User Experience Flow

### Starting a Call
1. User taps voice/video call button in chat
2. Backend emits `groupcall:started` event
3. Status bar slides down in chat
4. All participants see the status bar
5. Messaging hub shows call badge

### Joining a Call
1. User sees status bar or badge
2. Taps on status bar/conversation
3. App requests permissions if needed
4. Navigates to `GroupCallScreen`
5. WebRTC connection established

### During a Call
1. Participant count updates in real-time
2. Status bar shows current count
3. Messaging hub badge shows count
4. New joiners see updated count

### Ending a Call
1. Last person leaves
2. Backend emits `groupcall:stopped`
3. Status bar slides away
4. Badge removed from messaging hub
5. State cleaned up

## Visual Design

### Status Bar Colors
- **Video Call**: Purple gradient (`Colors.purple` → `Colors.deepPurple`)
- **Voice Call**: Green gradient (`Colors.green` → `Colors.teal`)

### Animation Details
- **Slide In**: 300ms ease-out animation from top
- **Pulse Effect**: 1000ms scale animation (0.8 to 1.2)
- **Shadow**: Colored shadow matching call type

### Responsive Layout
- **Mobile**: Full-width status bar
- **Icons**: Adaptive sizing (32px indicator, 18px icon)
- **Text**: Hierarchy with bold titles and subtle counts
- **Button**: White rounded join button with call color

## Technical Implementation

### Permission Handling
```dart
// Video calls - requires both
final res = await [Permission.microphone, Permission.camera].request();

// Voice calls - microphone only
final p = await Permission.microphone.request();
```

### State Management
- Uses `setState()` for local state updates
- StreamSubscriptions for socket events
- Proper cleanup in dispose()

### Error Handling
- Graceful fallbacks for missing data
- Try-catch blocks around socket events
- User feedback via CustomSnackbar

## Testing Guide

### Test Scenario 1: Call Initiation
1. **Device A**: Open pulse group chat
2. **Device A**: Tap voice or video call button
3. **Expected**: Status bar appears on Device A
4. **Device B**: Open same chat
5. **Expected**: Status bar appears on Device B
6. **Both**: Should show participant count

### Test Scenario 2: Joining from Status Bar
1. **Device B**: Tap status bar
2. **Expected**: Permission request appears
3. **Device B**: Grant permissions
4. **Expected**: Navigates to GroupCallScreen
5. **Both**: Participant count updates to 2

### Test Scenario 3: Messaging Hub
1. **Device C**: Open messaging hub
2. **Expected**: See call badge on active conversation
3. **Expected**: Badge shows "2 in call"
4. **Device C**: Tap conversation
5. **Expected**: Opens chat with status bar visible

### Test Scenario 4: Call Ending
1. **Device A**: Leave call
2. **Expected**: Count updates to 1
3. **Device B**: Leave call
4. **Expected**: Status bar disappears on all devices
5. **Expected**: Badge removed from messaging hub

### Test Scenario 5: State Persistence
1. Start call with 3 participants
2. Background the app
3. Return to app
4. **Expected**: Status bar still shows correct count
5. **Expected**: State properly maintained

## Edge Cases Handled

1. **Empty Participant List**: Shows "Tap to join" instead of count
2. **Call Ends While Viewing**: Status bar smoothly animates away
3. **Multiple Conversations**: Each tracks its own call state
4. **Permission Denied**: Shows warning snackbar, doesn't navigate
5. **Socket Disconnect**: State maintained, resyncs on reconnect

## Performance Considerations

1. **Animation Optimization**: Uses TweenAnimationBuilder for smooth 60fps
2. **State Updates**: Only updates when conversation ID matches
3. **Memory Management**: All subscriptions properly disposed
4. **Efficient Rendering**: Conditional rendering with `if` statements

## Future Enhancements

### Potential Additions:
1. **Avatar Display**: Show participant avatars in status bar
2. **Speaking Indicator**: Highlight who's currently speaking
3. **Quick Mute**: Mute button in status bar for participants
4. **Call Duration**: Show elapsed time
5. **Screen Share Indicator**: Badge when someone is screen sharing
6. **Pinned Status**: Keep status bar visible when scrolling
7. **Mini Preview**: Small video preview in status bar
8. **Notification Badge**: Show in app icon when call active

### Code Improvements:
1. Extract status bar to reusable component
2. Add unit tests for call state management
3. Implement state restoration for background/foreground
4. Add analytics tracking for call events
5. Localization for status text

## Comparison to Discord

| Feature | Discord | Our Implementation | Status |
|---------|---------|-------------------|--------|
| Status bar in channel | ✅ | ✅ | Complete |
| Participant count | ✅ | ✅ | Complete |
| Tap to join | ✅ | ✅ | Complete |
| Real-time updates | ✅ | ✅ | Complete |
| Visual indicator | ✅ | ✅ | Complete |
| Animation | ✅ | ✅ | Complete |
| Speaking indicator | ✅ | ❌ | Future |
| Video preview | ✅ | ❌ | Future |
| Screen share badge | ✅ | ❌ | Future |

## Troubleshooting

### Status Bar Not Appearing
- Check socket connection: `SocketService.instance.isConnected`
- Verify conversation ID matches
- Check console for event logs
- Ensure subscriptions are set up in `_setupSocketListeners()`

### Participant Count Wrong
- Check `groupcall:participants` event data
- Verify join/leave events are firing
- Check state updates in console logs
- Ensure proper cleanup on leave

### Join Button Not Working
- Check permission request logs
- Verify GroupCallScreen navigation
- Check if permissions are granted
- Ensure conversation ID is valid

## Monitoring & Debugging

### Console Logs
The implementation includes strategic logging:
```dart
print('[LiveGroupChat] Received socket message: ...');
print('[LiveGroupChat] Call started: video=$isVideo');
print('[LiveGroupChat] Participant count: $_callParticipantCount');
```

### State Inspection
Use Flutter DevTools to inspect:
- `_isCallActive` - Should match backend state
- `_callParticipantCount` - Should match actual participants
- `_callParticipants` - List of user IDs in call

## Security Considerations

1. **Permission Requests**: Always ask before accessing mic/camera
2. **Conversation Validation**: Backend validates membership
3. **State Sync**: Client state matches server state
4. **Error Handling**: Graceful fallbacks prevent crashes

## Accessibility

- **VoiceOver Support**: Status bar is tappable and announces state
- **High Contrast**: Colors chosen for visibility
- **Touch Targets**: Minimum 44x44pt tap areas
- **Haptic Feedback**: Confirms user actions

---

## Summary

This implementation provides a polished, Discord-style group call experience that keeps users informed about active calls and makes joining effortless. The status bar is visually prominent yet non-intrusive, and the real-time updates ensure users always see accurate call information.

**Key Achievement**: Users can now quickly see and join active group calls from both the chat page and messaging hub, significantly improving the group calling experience.
