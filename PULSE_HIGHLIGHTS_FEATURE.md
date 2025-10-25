# Pulse Highlights Feature

## Overview
Added Instagram-style highlights feature to Pulse, allowing users to create collections of their past/expired pulses that are displayed on their profile.

## Implementation Summary

### 1. Database Schema (Backend)
**File:** `backend/prisma/schema.prisma`
- Added `Highlight` model with fields:
  - `id`: Unique identifier
  - `title`: Name of the highlight collection
  - `coverUrl`: Optional cover image (defaults to first pulse image)
  - `userId`: Owner of the highlight
  - `position`: For ordering highlights on profile
  - `createdAt`, `updatedAt`: Timestamps
  - Relations to `User` and `Pulse` models

**Migration:** `20251025120006_add_pulse_highlights`

### 2. Backend API Routes
**File:** `backend/src/routes/highlights.ts`

Endpoints implemented:
- `GET /api/highlights/user/:userId` - Get all highlights for a user
- `GET /api/highlights/:id` - Get a specific highlight with all its pulses
- `POST /api/highlights` - Create a new highlight
- `PATCH /api/highlights/:id` - Update highlight (title, cover, add/remove pulses)
- `PUT /api/highlights/reorder` - Reorder highlights
- `DELETE /api/highlights/:id` - Delete a highlight
- `GET /api/highlights/user/:userId/pulses/available` - Get past pulses available for highlights

**File:** `backend/src/index.ts`
- Registered highlights routes

### 3. Flutter API Service
**File:** `pulse/lib/backend/api_service.dart`

Added methods:
- `getUserHighlights(String userId)` - Fetch user's highlights
- `getHighlight(String highlightId)` - Get highlight details
- `createHighlight({title, coverUrl, pulseIds})` - Create new highlight
- `updateHighlight({highlightId, title, coverUrl, addPulseIds, removePulseIds})` - Update highlight
- `reorderHighlights(List<String> highlightIds)` - Reorder highlights
- `deleteHighlight(String highlightId)` - Delete highlight
- `getAvailablePulsesForHighlights(String userId)` - Get past pulses

### 4. UI Components

#### Highlights Row Widget
**File:** `pulse/lib/components/highlights_row.dart`
- Horizontal scrollable list of highlight circles
- Shows highlight cover image and title
- "New" button for creating highlights (own profile only)
- Similar to Instagram's highlights row

#### Highlight Viewer Page
**File:** `pulse/lib/pages/highlights/highlight_viewer_page.dart`
- Full-screen story-like viewer for pulses in a highlight
- PageView for swiping between pulses
- Progress bars showing position in highlight
- Tap left/right to navigate
- Displays pulse image, title, description, date, and location
- Dark gradient overlay for text readability

#### Manage Highlight Page
**File:** `pulse/lib/pages/highlights/manage_highlight_page.dart`
- Create or edit highlights
- Title input field
- Grid of past pulses to select from
- Visual selection indicators
- Shows pulse images, titles, and dates

### 5. Profile Integration

#### Public Profile (ProfilePage.dart)
**File:** `pulse/lib/pages/profile/ProfilePage.dart`
- Added highlights row between stats and tabs
- Tapping highlights opens viewer
- Only shows highlights row if user has highlights

#### Own Profile (profile_widget.dart)
**File:** `pulse/lib/pages/profile/profile_widget.dart`
- Added highlights row with "New" button
- Create button opens manage highlights page
- Integrated into CustomScrollView

## Features

### User Features
1. **Create Highlights:** Group past/expired pulses into named collections
2. **View Highlights:** Story-like viewer with swipe navigation
3. **Edit Highlights:** Add/remove pulses, change title and cover
4. **Reorder Highlights:** Change the order of highlights on profile
5. **Delete Highlights:** Remove highlight collections

### Technical Features
1. **Automatic Cover Selection:** Uses first pulse image if no custom cover set
2. **Past Pulse Filtering:** Only shows pulses that have expired/ended
3. **Permission Control:** Users can only manage their own highlights
4. **Responsive UI:** Grid adapts for different screen sizes
5. **Smooth Animations:** Story-style progress bars and transitions

## Usage

### Creating a Highlight
1. Go to your profile
2. Tap the "New" button in the highlights row
3. Enter a title
4. Select past pulses from the grid
5. Tap "Create"

### Viewing Highlights
1. Tap any highlight circle on a profile
2. Swipe left/right or tap to navigate between pulses
3. Tap X to close

### Managing Highlights
1. Long-press or tap a highlight in edit mode
2. Modify title, cover, or pulses
3. Save changes

## Database Structure

```
Highlight
├── id (String, primary key)
├── title (String)
├── coverUrl (String?, optional)
├── userId (String, foreign key to User)
├── position (Int, for ordering)
├── createdAt (DateTime)
├── updatedAt (DateTime)
└── pulses (Many-to-many relation with Pulse)
```

## API Response Examples

### Get User Highlights
```json
[
  {
    "id": "highlight_123",
    "title": "Summer 2025",
    "coverUrl": "https://...",
    "pulseCount": 5,
    "pulses": [
      {
        "id": "pulse_abc",
        "title": "Beach Volleyball",
        "imageUrl": "https://...",
        "eventTime": "2025-07-15T14:00:00Z"
      }
    ]
  }
]
```

### Get Highlight Details
```json
{
  "id": "highlight_123",
  "title": "Summer 2025",
  "coverUrl": "https://...",
  "user": {
    "id": "user_xyz",
    "displayName": "John Doe",
    "profileImageUrl": "https://..."
  },
  "pulses": [
    {
      "id": "pulse_abc",
      "title": "Beach Volleyball",
      "description": "Fun day at the beach!",
      "imageUrl": "https://...",
      "eventTime": "2025-07-15T14:00:00Z",
      "location": {
        "name": "Santa Monica Beach",
        "city": "Los Angeles",
        "country": "USA"
      }
    }
  ]
}
```

## Design Decisions

1. **Past Pulses Only:** Highlights are meant for memories, so only expired pulses can be added
2. **Manual Cover:** Users can optionally set a custom cover, otherwise first pulse image is used
3. **Position Field:** Allows users to reorder their highlights for better organization
4. **Story-Style Viewer:** Familiar Instagram-like interface for better UX
5. **Lightweight Initial Load:** Only loads first pulse per highlight for the row, full data loaded on tap

## Future Enhancements

1. Add highlight categories/tags
2. Share highlights via link
3. Collaborative highlights (multiple users can add pulses)
4. Highlight analytics (views, engagement)
5. Export highlights as video or slideshow
6. Archive/unarchive highlights
7. Bulk operations on highlights
