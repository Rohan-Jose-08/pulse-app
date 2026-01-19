import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Modern draggable bottom sheet with smooth interactions
/// Follows 2026 design standards with rounded corners, drag handle, and smooth animations
class ModernBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final bool showDragHandle;
  final VoidCallback? onClose;

  const ModernBottomSheet({
    Key? key,
    required this.child,
    this.title,
    this.initialChildSize = 0.6,
    this.minChildSize = 0.3,
    this.maxChildSize = 0.95,
    this.showDragHandle = true,
    this.onClose,
  }) : super(key: key);

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double initialChildSize = 0.6,
    double minChildSize = 0.3,
    double maxChildSize = 0.95,
    bool showDragHandle = true,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        expand: false,
        builder: (context, scrollController) {
          return ModernBottomSheet(
            title: title,
            showDragHandle: showDragHandle,
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [child],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          if (showDragHandle)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.secondaryText.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

          // Title bar
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.headlineSmall,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                      color: theme.secondaryText,
                    ),
                ],
              ),
            ),

          // Content
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Quick action bottom sheet with list of options
class ActionBottomSheet extends StatelessWidget {
  final List<ActionSheetItem> actions;
  final String? title;
  final String? subtitle;

  const ActionBottomSheet({
    Key? key,
    required this.actions,
    this.title,
    this.subtitle,
  }) : super(key: key);

  static Future<T?> show<T>({
    required BuildContext context,
    required List<ActionSheetItem> actions,
    String? title,
    String? subtitle,
  }) {
    return ModernBottomSheet.show<T>(
      context: context,
      initialChildSize: 0.4,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      child: ActionBottomSheet(
        actions: actions,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: theme.headlineSmall,
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Action items
        ...actions.map((action) => _ActionItem(action: action)),

        // Bottom safe area
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }
}

class ActionSheetItem {
  final String title;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;
  final bool isDestructive;
  final bool isDismiss;

  const ActionSheetItem({
    required this.title,
    this.icon,
    required this.onTap,
    this.color,
    this.isDestructive = false,
    this.isDismiss = true,
  });
}

class _ActionItem extends StatelessWidget {
  final ActionSheetItem action;

  const _ActionItem({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final color = action.isDestructive
        ? theme.error
        : (action.color ?? theme.primaryText);

    return InkWell(
      onTap: () {
        if (action.isDismiss) {
          Navigator.of(context).pop();
        }
        action.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            if (action.icon != null) ...[
              Icon(
                action.icon,
                size: 24,
                color: color,
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                action.title,
                style: theme.bodyLarge.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modern confirmation dialog
class ModernConfirmDialog extends StatelessWidget {
  final String title;
  final String? message;
  final String confirmText;
  final String cancelText;
  final bool isDestructive;
  final VoidCallback? onConfirm;

  const ModernConfirmDialog({
    Key? key,
    required this.title,
    this.message,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
    this.isDestructive = false,
    this.onConfirm,
  }) : super(key: key);

  static Future<bool> show({
    required BuildContext context,
    required String title,
    String? message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ModernConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: theme.bodyMedium.copyWith(
                  color: theme.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: theme.alternate),
                    ),
                    child: Text(
                      cancelText,
                      style: theme.bodyLarge.copyWith(
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      onConfirm?.call();
                      Navigator.of(context).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDestructive ? theme.error : theme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      confirmText,
                      style: theme.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
