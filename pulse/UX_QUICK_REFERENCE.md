# 🎯 UX Quick Reference Card

## 🚀 Common Patterns - Copy & Paste Ready

### 1. Loading States

```dart
// ❌ DON'T use this:
loading: () => const Center(child: CircularProgressIndicator())

// ✅ DO use this instead:
loading: () => SkeletonListView(
  itemCount: 5,
  itemBuilder: (context, index) => const ConversationItemSkeleton(),
)
```

---

### 2. Error States

```dart
// ❌ DON'T use this:
error: (_, __) => const Center(child: Text('Error loading data'))

// ✅ DO use this instead:
error: (_, __) => ErrorStateWidget(
  message: 'Failed to load conversations',
  onRetry: _loadData,
)
```

---

### 3. Empty States

```dart
// ❌ DON'T use this:
if (items.isEmpty) return Center(child: Text('No items'));

// ✅ DO use this instead:
if (items.isEmpty) {
  return EmptyStateWidget(
    title: 'No Conversations',
    message: 'Start chatting with people nearby!',
    icon: Icons.chat_bubble_outline,
    actionText: 'Find People',
    onAction: _navigateToDiscovery,
  );
}
```

---

### 4. Snackbar Notifications

```dart
// ❌ DON'T use this:
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Success!')),
)

// ✅ DO use this instead:

// Success:
CustomSnackbar.showSuccess(context, message: 'Pulse created! 🎉')

// Error with retry:
CustomSnackbar.showError(
  context,
  message: 'Failed to send message',
  actionLabel: 'Retry',
  onAction: _retrySend,
)

// Info:
CustomSnackbar.showInfo(context, message: 'Syncing...')

// Warning:
CustomSnackbar.showWarning(context, message: 'Location permission needed')
```

---

### 5. Haptic Feedback

```dart
// ❌ DON'T forget haptics on interactive elements

// ✅ DO add haptics:

// Light (for selection/navigation):
await HapticUtils.light();

// Medium (for button press):
await HapticUtils.medium();

// Heavy (for significant actions):
await HapticUtils.heavy();

// Success/Error/Warning:
await HapticUtils.success();
await HapticUtils.error();
await HapticUtils.warning();

// Or use HapticButton:
HapticButton(
  onPressed: _handlePress,
  feedbackType: HapticsType.medium,
  child: Text('Press Me'),
)
```

---

### 6. Form Validation

```dart
// ❌ DON'T use manual validation

// ✅ DO use validators:

TextFormField(
  controller: _emailController,
  decoration: InputDecoration(
    labelText: 'Email',
    prefixIcon: Icon(Icons.email),
  ),
  validator: FormValidators.email, // Built-in email validator
)

TextFormField(
  controller: _passwordController,
  obscureText: true,
  decoration: InputDecoration(
    labelText: 'Password',
    prefixIcon: Icon(Icons.lock),
  ),
  validator: FormValidators.password, // Strong password validator
)

// Custom validation:
validator: (value) => FormValidators.minLength(value, 3, fieldName: 'Title')
```

---

### 7. Pull to Refresh

```dart
// ❌ DON'T use plain RefreshIndicator

// ✅ DO use CustomRefreshIndicator:

return CustomRefreshIndicator(
  onRefresh: _refreshData,
  child: ListView(...),
)
```

---

### 8. Animated Cards

```dart
// ❌ DON'T use plain Card or GestureDetector

// ✅ DO use AnimatedCard or HapticCard:

HapticCard(
  onTap: _openDetails,
  child: Row(
    children: [
      CircleAvatar(...),
      Expanded(child: Text(name)),
    ],
  ),
)
```

---

### 9. List Item Animations

```dart
// ❌ DON'T show items instantly

// ✅ DO add slide-in animation:

ListView.builder(
  itemBuilder: (context, index) => SlideInAnimation(
    index: index,
    child: ConversationCard(...),
  ),
)
```

---

### 10. Loading Dialog

```dart
// ❌ DON'T block UI without feedback

// ✅ DO show loading dialog:

LoadingDialog.show(context, message: 'Creating pulse...');

try {
  await createPulse();
  LoadingDialog.hide(context);
  CustomSnackbar.showSuccess(context, message: 'Created!');
} catch (e) {
  LoadingDialog.hide(context);
  CustomSnackbar.showError(context, message: 'Failed');
}
```

---

### 11. Confirmation Dialog

```dart
// ❌ DON'T use default AlertDialog

// ✅ DO use ConfirmDialog:

final confirmed = await ConfirmDialog.show(
  context,
  title: 'Delete Pulse?',
  message: 'This action cannot be undone',
  confirmText: 'Delete',
  isDestructive: true, // Makes it red
);

if (confirmed == true) {
  // User confirmed
}
```

---

### 12. Feature Discovery Tooltip

```dart
// ✅ Wrap important features with tooltip:

FeatureDiscoveryTooltip(
  featureId: 'create_pulse_button',
  title: 'Create a Pulse',
  description: 'Tap here to create your first event!',
  position: TooltipPosition.bottom,
  child: FloatingActionButton(
    onPressed: _createPulse,
    child: Icon(Icons.add),
  ),
)
```

---

## 📋 Checklist for New Pages

When creating a new page, ensure:

- [ ] Loading state uses skeleton loaders
- [ ] Error state uses ErrorStateWidget with retry
- [ ] Empty state uses EmptyStateWidget
- [ ] Lists have pull-to-refresh
- [ ] Interactive elements have haptic feedback
- [ ] Success/error actions show snackbars
- [ ] Forms use validators
- [ ] Cards use AnimatedCard or HapticCard
- [ ] List items have SlideInAnimation
- [ ] Important features have tooltips

---

## 🎨 Component Import Guide

```dart
// Loading & Error States:
import '../components/skeleton_loader.dart';
import '../components/error_state_widget.dart';

// Interactions:
import '../components/micro_interactions.dart';
import '../components/refresh_indicator.dart';

// Utilities:
import '../utils/haptic_utils.dart';
import '../utils/snackbar_utils.dart';
import '../utils/form_validators.dart';

// Onboarding:
import '../components/onboarding_tooltip.dart';

// For haptics:
import 'package:haptic_feedback/haptic_feedback.dart';
```

---

## 🔥 Hot Tips

1. **Always provide feedback** - Every user action should have a response
2. **Haptics matter** - Test on real devices, not just simulator
3. **Skeleton > Spinner** - Better perceived performance
4. **Friendly errors** - Avoid technical jargon in error messages
5. **Retry buttons** - Always give users a way to recover
6. **Test in dark mode** - Ensure all components look good
7. **Subtle animations** - Less is more
8. **Form feedback** - Validate as user types, not just on submit

---

## 🚨 Common Mistakes to Avoid

❌ Using CircularProgressIndicator directly  
❌ Showing technical error messages  
❌ Forgetting haptic feedback on buttons  
❌ Not providing retry functionality  
❌ Using plain AlertDialog for confirmations  
❌ Skipping pull-to-refresh on lists  
❌ No validation feedback on forms  
❌ Instant list item appearance (no animation)  

---

## 💾 Save This!

Bookmark this page for quick reference when:
- Creating new pages
- Refactoring existing code
- Reviewing PRs
- Training new team members

---

**Last Updated**: October 2025  
**Version**: 1.0  
**For**: Pulse App Development Team
