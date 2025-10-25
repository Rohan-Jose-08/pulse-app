# Quick Reference - Pulse App Design System

## 🎨 Common Patterns

### Page Structure
```dart
Scaffold(
  backgroundColor: theme.primaryBackground,
  appBar: AppBar(
    backgroundColor: theme.secondaryBackground,
    elevation: 0,
    title: Text('Title', style: theme.headlineSmall),
  ),
  body: ModernRefreshIndicator(
    onRefresh: _handleRefresh,
    child: ListView(
      padding: EdgeInsets.all(AppSpacing.m),
      children: [
        // Your content
      ],
    ),
  ),
  floatingActionButton: AnimatedFAB(
    icon: Icons.add,
    onPressed: _handleAdd,
  ),
)
```

### List Item with Avatar
```dart
ModernCard(
  onTap: () => _handleTap(item),
  child: Row(
    children: [
      PulseAvatar(
        imageUrl: item.avatar,
        showOnlineStatus: true,
        isOnline: item.isOnline,
      ),
      SizedBox(width: AppSpacing.m),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: theme.titleMedium),
            Text(item.subtitle, style: theme.bodySmall),
          ],
        ),
      ),
      StatusBadge(text: 'Active', color: theme.success),
    ],
  ),
)
```

### Form Field
```dart
ModernTextField(
  controller: _controller,
  label: 'Email',
  hint: 'Enter your email',
  prefixIcon: Icons.email,
  keyboardType: TextInputType.emailAddress,
  validator: (value) {
    if (value?.isEmpty ?? true) return 'Required';
    return null;
  },
)
```

### Action Buttons
```dart
Row(
  children: [
    Expanded(
      child: GradientButton(
        text: 'Cancel',
        isOutlined: true,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    SizedBox(width: AppSpacing.m),
    Expanded(
      child: GradientButton(
        text: 'Save',
        icon: Icons.check,
        isLoading: _isSaving,
        onPressed: _handleSave,
      ),
    ),
  ],
)
```

### Loading State
```dart
if (_isLoading)
  Column(
    children: List.generate(5, (i) => 
      ModernCard(
        child: Row(
          children: [
            ShimmerLoading(width: 48, height: 48, shape: BoxShape.circle),
            SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                children: [
                  ShimmerLoading(width: double.infinity, height: 16),
                  SizedBox(height: AppSpacing.s),
                  ShimmerLoading(width: 150, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  )
```

### Empty State
```dart
if (_items.isEmpty)
  EmptyStateWidget(
    title: 'No Items',
    message: 'Get started by adding your first item',
    icon: Icons.inbox,
    actionText: 'Add Item',
    onAction: _handleAdd,
  )
```

### Staggered List
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return StaggeredListAnimation(
      index: index,
      child: ModernCard(child: ItemWidget(items[index])),
    );
  },
)
```

### Bottom Sheet
```dart
ModernBottomSheet.show(
  context: context,
  title: 'Options',
  child: Column(
    children: [
      ListTile(title: Text('Option 1'), onTap: () {}),
      ListTile(title: Text('Option 2'), onTap: () {}),
    ],
  ),
)
```

### Snackbar
```dart
// Success
ModernSnackbar.show(
  context: context,
  message: 'Saved successfully!',
  type: SnackbarType.success,
)

// Error
ModernSnackbar.show(
  context: context,
  message: 'Something went wrong',
  type: SnackbarType.error,
)
```

### Confirmation Dialog
```dart
final confirmed = await ConfirmationDialog.show(
  context: context,
  title: 'Delete Item?',
  message: 'This action cannot be undone',
  confirmText: 'Delete',
  isDangerous: true,
);

if (confirmed == true) {
  // Handle deletion
}
```

### Loading Overlay
```dart
LoadingOverlay.show(context, message: 'Processing...');
await Future.delayed(Duration(seconds: 2));
LoadingOverlay.hide(context);
```

## 🎯 Animation Examples

### Entrance Animation
```dart
SlideInFromBottom(
  delay: Duration(milliseconds: 100),
  child: MyWidget(),
)
```

### Success Feedback
```dart
BounceAnimation(
  trigger: _showSuccess,
  child: Icon(Icons.check_circle, color: theme.success, size: 64),
)
```

### Error Feedback
```dart
ShakeAnimation(
  trigger: _hasError,
  child: ModernTextField(...),
)
```

### Attention Grabber
```dart
PulseAnimation(
  isPulsing: true,
  pulseColor: theme.primary,
  child: Icon(Icons.notifications),
)
```

## 📐 Spacing Guide

```dart
// Tiny gaps
SizedBox(height: AppSpacing.xs)  // 4px

// Small gaps
SizedBox(height: AppSpacing.s)   // 8px

// Standard gaps
SizedBox(height: AppSpacing.m)   // 16px

// Large gaps
SizedBox(height: AppSpacing.l)   // 24px

// Extra large gaps
SizedBox(height: AppSpacing.xl)  // 32px

// Section separators
SizedBox(height: AppSpacing.xxl) // 48px
```

## 🎨 Color Usage

```dart
// Primary actions
GradientButton(text: 'Primary Action')

// Success states
StatusBadge(text: 'Success', color: theme.success)
Container(color: theme.success)

// Warning states
StatusBadge(text: 'Warning', color: theme.warning)

// Error states
StatusBadge(text: 'Error', color: theme.error)
Text('Error message', style: theme.bodyMedium.override(color: theme.error))

// Info states
StatusBadge(text: 'Info', color: theme.info)
```

## 📱 Responsive Patterns

```dart
// Max width for readability
Center(
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 600),
    child: YourContent(),
  ),
)

// Responsive grid
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
    crossAxisSpacing: AppSpacing.m,
    mainAxisSpacing: AppSpacing.m,
  ),
  itemBuilder: (context, index) => ModernCard(child: ...),
)
```

## ⚡ Performance Tips

```dart
// Use const where possible
const SizedBox(height: AppSpacing.m)

// Cache network images
CachedNetworkImage(
  imageUrl: url,
  placeholder: (context, url) => ShimmerLoading(...),
)

// Dispose controllers
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

// Use keys for lists
ListView.builder(
  itemBuilder: (context, index) {
    return ModernCard(
      key: ValueKey(items[index].id),
      child: ...,
    );
  },
)
```

## 🎭 Theme Access

```dart
// Get theme
final theme = FlutterFlowTheme.of(context);

// Use theme colors
Container(color: theme.primary)
Text('Text', style: theme.titleMedium)

// Override styles
Text(
  'Text',
  style: theme.bodyLarge.override(
    color: theme.success,
    fontWeight: FontWeight.bold,
  ),
)
```

---

**Remember**: Consistency is key! Use these patterns throughout your app for a cohesive experience.
