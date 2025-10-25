# Pulse Highlights - Quick Reference Guide

## For Users

### Creating Your First Highlight
1. **Navigate to Your Profile**
   - Tap the profile icon in the bottom navigation

2. **Create a Highlight**
   - Look for the circular "New" button in the highlights row (below your profile stats)
   - Tap the "New" button
   - Enter a title for your highlight (e.g., "Summer 2025", "Concerts", "Adventures")
   - Select past pulses from the grid (only expired pulses are shown)
   - Tap "Create"

### Viewing Highlights
- **Your Highlights:** Scroll horizontally through the circles on your profile
- **Others' Highlights:** View on any user's profile page
- **Open Viewer:** Tap any highlight circle to view pulses in full-screen
- **Navigate:** Swipe left/right or tap left/right side of screen
- **Exit:** Tap the X button in the top-right

### Managing Highlights
1. **Edit a Highlight**
   - Long-press a highlight (feature to be added in future update)
   - Or navigate to highlight and select edit option

2. **Delete a Highlight**
   - Edit the highlight
   - Select delete option
   - Confirm deletion

## For Developers

### Backend API Endpoints

```typescript
// Get user's highlights
GET /api/highlights/user/:userId
Response: Array<Highlight>

// Get highlight details
GET /api/highlights/:id
Response: Highlight (with pulses)

// Create highlight
POST /api/highlights
Body: { title: string, coverUrl?: string, pulseIds?: string[] }
Response: Highlight

// Update highlight
PATCH /api/highlights/:id
Body: { title?: string, coverUrl?: string, addPulseIds?: string[], removePulseIds?: string[] }
Response: Highlight

// Reorder highlights
PUT /api/highlights/reorder
Body: { highlightIds: string[] }
Response: { success: true }

// Delete highlight
DELETE /api/highlights/:id
Response: { success: true }

// Get available pulses (expired/past)
GET /api/highlights/user/:userId/pulses/available
Response: Array<Pulse>
```

### Flutter Widgets

```dart
// Highlights Row (horizontal scrolling)
HighlightsRow(
  userId: 'user_123',
  isOwnProfile: true,
  onHighlightTap: (highlight) { /* navigate to viewer */ },
  onCreateTap: () { /* navigate to create page */ },
)

// Highlight Viewer (full-screen story view)
HighlightViewerPage(
  highlightId: 'highlight_123',
  initialIndex: 0, // optional, defaults to 0
)

// Manage Highlight (create/edit)
ManageHighlightPage(
  highlightId: 'highlight_123', // null for new highlight
  initialTitle: 'My Highlight', // optional
)
```

### API Service Methods

```dart
final api = ApiService.instance;

// Get highlights
final highlights = await api.getUserHighlights(userId);

// Get highlight details
final highlight = await api.getHighlight(highlightId);

// Create highlight
final newHighlight = await api.createHighlight(
  title: 'Summer 2025',
  pulseIds: ['pulse1', 'pulse2'],
);

// Update highlight
final updated = await api.updateHighlight(
  highlightId: highlightId,
  title: 'New Title',
  addPulseIds: ['pulse3'],
  removePulseIds: ['pulse1'],
);

// Reorder highlights
final success = await api.reorderHighlights(
  ['highlight2', 'highlight1', 'highlight3'],
);

// Delete highlight
final deleted = await api.deleteHighlight(highlightId);

// Get past pulses
final pastPulses = await api.getAvailablePulsesForHighlights(userId);
```

### Database Schema

```prisma
model Highlight {
  id          String   @id @default(cuid())
  title       String
  coverUrl    String?
  userId      String
  position    Int      @default(0)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
  
  user        User     @relation("UserHighlights", fields: [userId], references: [id], onDelete: Cascade)
  pulses      Pulse[]  @relation("HighlightPulses")
  
  @@index([userId])
  @@index([userId, position])
}
```

## Key Features

✅ **Instagram-Style UI** - Familiar circular highlights with cover images
✅ **Story Viewer** - Full-screen swipe navigation through pulses
✅ **Automatic Covers** - First pulse image used if no custom cover
✅ **Past Pulses Only** - Only expired pulses can be added
✅ **Reorderable** - Drag to reorder highlights (feature planned)
✅ **Public/Private** - Visible on all profiles
✅ **Responsive** - Adapts to different screen sizes

## Design Patterns

### Highlight Circle
- 68x68 pixel circle
- 2.5px border (primary color)
- 3px inner padding
- Title below (max 1 line)
- Pulse count indicator

### Viewer
- Black background
- Progress bars at top
- User info header
- Gradient overlay on image
- Info panel at bottom
- Tap zones for navigation

### Management Grid
- 3 columns on mobile
- 0.75 aspect ratio
- Selection checkmark overlay
- Image preview with gradient
- Title and date labels

## Common Issues & Solutions

### Issue: Highlights not showing
**Solution:** Ensure the user has expired pulses. Only past pulses can be added to highlights.

### Issue: Cover image not displaying
**Solution:** Check if coverUrl is set. If null, ensure at least one pulse has an imageUrl.

### Issue: Can't create highlight
**Solution:** Verify user authentication and that they have permission to create highlights for their own profile.

### Issue: Pulses not loading
**Solution:** Check that pulses have `activeUntil < now` or `eventTime < now` (for pulses without activeUntil).

## Testing Checklist

- [ ] Create highlight with title
- [ ] Add multiple pulses to highlight
- [ ] View highlight in story viewer
- [ ] Navigate between pulses (swipe and tap)
- [ ] Edit highlight title
- [ ] Add pulse to existing highlight
- [ ] Remove pulse from highlight
- [ ] Change highlight cover
- [ ] Reorder highlights
- [ ] Delete highlight
- [ ] View others' highlights
- [ ] Empty state (no highlights)
- [ ] Empty state (no past pulses)

## Next Steps

1. Add long-press menu for highlight management
2. Implement drag-to-reorder for highlights
3. Add share functionality
4. Add highlight analytics
5. Support video pulses in highlights
6. Add highlight categories/tags
7. Collaborative highlights (multiple owners)
