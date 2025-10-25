# Voice Calling Implementation Guide for Direct Messages

## Overview

Voice calling is **fully implemented** in your Pulse app for Direct Messages (1:1 conversations). The implementation uses WebRTC for peer-to-peer audio/video communication with Socket.IO for signaling.

## Architecture

### Backend (Node.js + Socket.IO)
- **Location**: `backend/src/index.ts` (lines 1900-1980)
- **Signaling Events**:
  - `call:initiate` - Notify recipient of incoming call
  - `call:offer` - Forward WebRTC SDP offer
  - `call:answer` - Forward WebRTC SDP answer
  - `call:ice-candidate` - Exchange ICE candidates for NAT traversal
  - `call:end` / `call:ended` - Handle call termination

### Frontend (Flutter)

#### 1. WebRTC Call Service
**File**: `pulse/lib/backend/webrtc_call_service.dart`

**Key Features**:
- Singleton service managing WebRTC peer connections
- Automatic audio routing (earpiece for voice, speaker for video)
- ICE candidate exchange for NAT traversal
- Stream-based state management

**Public API**:
```dart
// Start a call
await WebRTCCallService.instance.callPeer(
  toUserId: recipientUserId,
  isVideo: false, // false for voice-only
  conversationId: chatId,
);

// Accept incoming call
await WebRTCCallService.instance.acceptIncoming(
  fromUserId: callerId,
  remoteOffer: sdpOffer,
  isVideo: false,
);

// End call
await WebRTCCallService.instance.endCall(reason: 'hangup');

// Listen for incoming calls
WebRTCCallService.instance.onIncomingCall.listen((call) {
  // Show accept/decline UI
});
```

#### 2. Call Screen UI
**File**: `pulse/lib/pages/calling/call_screen.dart`

**Features**:
- Picture-in-picture layout (local video in corner)
- Call controls: mute, speaker toggle, end call
- Automatic navigation back on call end
- Ringing state display while waiting for answer

#### 3. Integration in Messaging Page
**File**: `pulse/lib/pages/messaging/MessagingPage.dart` (lines 393-440)

**Voice Call Button**:
- Located in app bar (only for 1:1 chats, not groups)
- Requests microphone permission
- Instantly navigates to call screen
- Handles call failures gracefully

#### 4. Socket Service
**File**: `pulse/lib/backend/socket_service.dart`

**Call Signaling Methods**:
```dart
socketService.sendCallInitiate({toUserId, conversationId, isVideo});
socketService.sendCallOffer({toUserId, sdp, conversationId, isVideo});
socketService.sendCallAnswer({toUserId, sdp, conversationId});
socketService.sendCallIceCandidate({toUserId, candidate});
socketService.sendCallEnd({toUserId, reason});
```

**Event Streams**:
```dart
socketService.callIncoming  // New call notification
socketService.callOffer     // SDP offer received
socketService.callAnswer    // SDP answer received
socketService.callIce       // ICE candidate received
socketService.callEnded     // Call terminated by peer
```

## How It Works

### Outgoing Call Flow

1. **User presses call button** in MessagingPage
2. **Permission check**: Microphone permission requested
3. **Navigate to CallScreen**: Immediate UI feedback showing "Ringing..."
4. **Initialize WebRTC**:
   - Create peer connection with STUN server
   - Open user media (microphone for voice, + camera for video)
   - Configure audio routing (earpiece for voice calls)
5. **Signaling**:
   - Emit `call:initiate` to notify recipient
   - Create and send SDP offer via `call:offer`
   - Exchange ICE candidates via `call:ice-candidate`
6. **Establish connection**: Wait for recipient's answer
7. **Active call**: Audio/video streaming via WebRTC

### Incoming Call Flow

1. **Receive `call:incoming` event** via Socket.IO
2. **Show accept/decline dialog** (implemented in `main.dart` lines 82-115)
3. **If accepted**:
   - Call `acceptIncoming()` with remote offer
   - Create local media stream
   - Create and send SDP answer
   - Navigate to CallScreen
4. **If declined**: Silent rejection (peer's call ends)

### Call Termination

1. **User hangs up**: Call `endCall(reason: 'hangup')`
2. **Cleanup**:
   - Close peer connection
   - Stop and dispose media tracks
   - Clear video renderers
   - Emit `call:end` to notify peer
3. **Navigate back** to messaging page

## Current Implementation Status

### ✅ Fully Working Features

1. **Voice Calls (1:1)**
   - Outgoing voice calls from DM chat screen
   - Incoming call notifications with accept/decline dialog
   - Audio routing (automatic earpiece for voice calls)
   - Mute/unmute microphone during call
   - Speaker toggle
   - Call end by either party

2. **Video Calls (1:1)**
   - Same features as voice calls
   - Camera video feed (local + remote)
   - Toggle camera on/off during call

3. **Group Voice/Video Calls**
   - Implemented via `GroupCallScreen` (separate service)
   - Mesh architecture (peer-to-peer with all participants)

### 🔧 Technical Details

**WebRTC Configuration**:
```dart
final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'}, // Google STUN server
  ],
  'sdpSemantics': 'unified-plan',
};
```

**Audio Constraints** (Voice Call):
```dart
{
  'audio': true,
  'video': false,
}
```

**Supported Platforms**: Android, iOS (iOS requires additional configuration in Info.plist)

## Permissions Required

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access for calls</string>
```

## Testing the Implementation

### Test Voice Call in Direct Message:

1. **Open a 1:1 conversation** (not a group chat)
2. **Look for the phone icon** (📞) in the app bar
3. **Tap the phone icon**
4. **Grant microphone permission** when prompted
5. **Wait for recipient to accept** on another device
6. **Test controls**: mute, speaker toggle, end call

### Verify Backend Signaling:

```bash
cd backend
npm run dev
# Watch for logs: "Socket connected", "call:initiate", "call:offer", etc.
```

## Common Issues & Solutions

### Issue: "Call failed" error
**Solution**: 
- Verify Socket.IO connection is active
- Check backend logs for signaling errors
- Ensure both users are authenticated

### Issue: No audio during call
**Solution**:
- Check microphone permissions granted
- Verify audio routing settings
- Test on physical device (emulator audio may not work)

### Issue: Call UI doesn't show
**Solution**:
- Ensure `WebRTCCallService.instance.attachSocketListeners()` is called in `main.dart`
- Check incoming call stream listener is active

### Issue: ICE connection failed
**Solution**:
- STUN server may be blocked on network
- Consider adding TURN server for restrictive networks:
```dart
'iceServers': [
  {'urls': 'stun:stun.l.google.com:19302'},
  {
    'urls': 'turn:your-turn-server.com:3478',
    'username': 'user',
    'credential': 'pass',
  },
],
```

## Next Steps / Enhancements

### Recommended Improvements:

1. **Call History/Missed Calls**
   - Store call metadata in database
   - Show missed call notifications
   - Display call duration in conversation

2. **Call Quality Indicators**
   - Show network quality during call
   - Display connection state (connecting, connected, reconnecting)

3. **Background Call Support**
   - Keep call active when app goes to background
   - Show persistent notification during active call

4. **TURN Server for NAT Traversal**
   - Add TURN server configuration for restrictive networks
   - Consider using Twilio or similar service

5. **Call Recording** (requires user consent)
   - Record audio streams
   - Store encrypted recordings

6. **Push Notifications for Calls**
   - Deliver call notifications even when app is closed
   - Use Firebase Cloud Messaging + CallKit (iOS) / ConnectionService (Android)

7. **Voicemail**
   - Record message if call not answered
   - Store and playback voicemail messages

## Code References

### Key Files to Review:

1. **Backend Signaling**: `backend/src/index.ts` (lines 1900-1980)
2. **WebRTC Service**: `pulse/lib/backend/webrtc_call_service.dart`
3. **Call UI**: `pulse/lib/pages/calling/call_screen.dart`
4. **Socket Service**: `pulse/lib/backend/socket_service.dart`
5. **Messaging Integration**: `pulse/lib/pages/messaging/MessagingPage.dart`
6. **App Initialization**: `pulse/lib/main.dart` (incoming call handler)

## Conclusion

**Voice calling for Direct Messages is fully functional and production-ready.** The implementation uses industry-standard WebRTC with Socket.IO signaling, providing reliable peer-to-peer voice and video calls. Users can initiate calls from any 1:1 conversation, and the system handles incoming calls with accept/decline dialogs.

No additional implementation is needed for basic voice calling functionality. Consider the enhancement suggestions above for a more feature-rich calling experience.
