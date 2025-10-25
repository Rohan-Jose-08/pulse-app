# Video Highlight Capture - Implementation Guide

## Overview
Instagram-style video highlights for Pulse events. Users can record short videos (up to 60 seconds) during active pulses, which are then saved as highlights associated with that pulse.

## Features Implemented

### 1. Video Capture Screen (`video_capture_page.dart`)
**Location:** `pulse/lib/pages/highlights/video_capture_page.dart`

**Features:**
- ✅ Real-time camera preview with front/back camera toggle
- ✅ Record button with visual feedback (white circle → red square when recording)
- ✅ Recording timer with progress bar (max 60 seconds)
- ✅ Auto-stop at max duration
- ✅ Recording indicator (red dot + timer)
- ✅ Haptic feedback on start/stop
- ✅ Display pulse name context

**UI Elements:**
- Top bar: Close button, recording timer, flip camera button
- Bottom: Pulse name label, record button (tap to start/stop)
- Progress bar showing time remaining

### 2. Video Preview Screen (`video_preview_page.dart`)
**Location:** `pulse/lib/pages/highlights/video_preview_page.dart`

**Features:**
- ✅ Video playback with tap-to-pause/play
- ✅ Auto-loop preview
- ✅ Caption input (up to 150 characters)
- ✅ Public/Private toggle
- ✅ Video upload to Firebase Storage
- ✅ Thumbnail generation from video
- ✅ Upload progress indicator
- ✅ API integration to create highlight

**Upload Flow:**
1. Upload video to Firebase Storage (`highlights/videos/`)
2. Generate thumbnail from first frame
3. Upload thumbnail to Firebase Storage (`highlights/thumbnails/`)
4. Call backend API to create highlight record
5. Return to pulse detail page on success

### 3. Integration with Pulse Detail Page
**Location:** `pulse/lib/pages/pulse_detail/pulse_detail_page.dart`

**Added:**
- Camera icon button in app bar (next to share button)
- Only enabled during active pulses
- Shows error message if pulse is not active
- Refreshes pulse details after highlight creation

## Dependencies Added

```yaml
camera: ^0.10.5+9          # Camera access and recording
video_player: ^2.8.2       # Video playback
video_thumbnail: ^0.5.3    # Generate thumbnails from videos
```

## Usage Flow

### Creating a Highlight:
1. User opens an active pulse detail page
2. Taps camera icon in app bar
3. Records video (up to 60 seconds)
4. Reviews video in preview screen
5. Adds optional caption
6. Chooses public/private visibility
7. Taps "Share Highlight" button
8. Video uploads to Firebase Storage
9. Highlight created via backend API
10. Returns to pulse detail page

### Permissions Required:
- **Camera**: Required for video recording
- **Microphone**: Required for audio in videos
- **Storage**: Required for saving video files

## Backend API Integration

### Create Highlight Endpoint
```dart
POST /api/highlights
{
  "videoUrl": "https://firebase.storage.../video.mp4",
  "thumbnailUrl": "https://firebase.storage.../thumb.jpg",
  "duration": 30,           // seconds
  "pulseId": "pulse123",
  "caption": "Great moment!", // optional
  "isPublic": true          // default true
}
```

### Response
```dart
{
  "id": "highlight123",
  "videoUrl": "...",
  "thumbnailUrl": "...",
  "duration": 30,
  "caption": "Great moment!",
  "pulseId": "pulse123",
  "userId": "user123",
  "isPublic": true,
  "viewCount": 0,
  "createdAt": "2025-10-25T...",
  "updatedAt": "2025-10-25T..."
}
```

## UI/UX Design

### Video Capture Screen
- **Background**: Full-screen camera preview
- **Top Controls**: Translucent black background (0.5 opacity)
  - Close button (left)
  - Recording timer with red dot (center, when recording)
  - Flip camera button (right)
- **Bottom Controls**: 
  - Pulse name badge with translucent background
  - Large circular record button (80x80)
  - Processing indicator (when stopping)
- **Progress Bar**: Linear indicator at top showing recording progress

### Video Preview Screen
- **Background**: Full-screen video player
- **Play/Pause**: Tap anywhere on video
- **Overlay Icons**: Play icon when paused
- **Bottom Gradient**: Dark gradient for controls visibility
- **Controls Panel**:
  - Caption text field (translucent white background)
  - Public/Private toggle with switch
  - Primary action button "Share Highlight"
  - Upload progress bar (when uploading)

## Error Handling

### Camera Initialization Errors
- No cameras available
- Permission denied
- Camera in use by another app

### Recording Errors
- Disk space full
- Recording failed to start/stop
- Invalid camera state

### Upload Errors
- No internet connection
- Firebase upload failed
- Thumbnail generation failed
- API call failed

All errors display user-friendly SnackBar messages.

## File Structure

```
pulse/lib/pages/highlights/
├── video_capture_page.dart    # Camera recording screen
├── video_preview_page.dart    # Preview and upload screen
├── highlight_viewer_page.dart # (Existing) View highlights
└── manage_highlight_page.dart # (Existing) Manage highlights
```

## Firebase Storage Structure

```
highlights/
├── videos/
│   └── {timestamp}-{filename}.mp4
└── thumbnails/
    └── {timestamp}-{filename}.jpg
```

## Next Steps

### Still To Implement:
1. **Update Highlight Viewer** - Modify viewer to play videos instead of showing images
2. **Update Highlights Row** - Show video thumbnails with play icon overlay and duration badge
3. **Video Compression** - Compress videos before upload to reduce bandwidth
4. **Better Thumbnail Generation** - Extract frame at specific timestamp (e.g., 2 seconds in)
5. **Video Filters** - Add Instagram-style filters during recording
6. **Music/Audio** - Allow adding background music
7. **Text Overlays** - Add text/stickers during recording
8. **Trim Video** - Allow trimming video before upload

## Testing Checklist

- [ ] Test camera permission request
- [ ] Test front/back camera switching
- [ ] Test recording start/stop
- [ ] Test auto-stop at 60 seconds
- [ ] Test video preview playback
- [ ] Test caption input (including 150 char limit)
- [ ] Test public/private toggle
- [ ] Test upload progress
- [ ] Test Firebase Storage upload
- [ ] Test API integration
- [ ] Test error scenarios (no internet, etc.)
- [ ] Test on different screen sizes
- [ ] Test on iOS and Android

## Known Limitations

1. **Max Duration**: Hard-coded to 60 seconds
2. **No Video Editing**: Can't trim or edit after recording
3. **No Filters**: No real-time filters during recording
4. **Single Take**: Must re-record if not satisfied (no retake from preview)
5. **No Draft Saving**: Videos are lost if user cancels

## Performance Considerations

- Videos are compressed at "high" resolution preset
- Thumbnails generated at 720px width
- Upload progress tracked in real-time
- Video controller properly disposed to prevent memory leaks
- Camera released when app goes to background

## Accessibility

- All buttons have semantic labels
- Error messages are screen-reader friendly
- Haptic feedback for important actions
- Visual feedback for all states (recording, processing, uploading)

---

**Last Updated**: October 25, 2025
**Version**: 1.0.0
