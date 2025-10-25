import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';

/// Enhanced Text Field with modern styling
class ModernTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int? maxLines;
  final bool enabled;

  const ModernTextField({
    Key? key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<ModernTextField> createState() => _ModernTextFieldState();
}

class _ModernTextFieldState extends State<ModernTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.labelMedium.override(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.s),
        ],
        Focus(
          onFocusChange: (focused) {
            setState(() => _isFocused = focused);
          },
          child: AnimatedContainer(
            duration: AppAnimation.fast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.m),
              border: Border.all(
                color: _isFocused ? theme.primary : theme.alternate,
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: theme.primary.withOpacity(0.1),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: TextFormField(
              controller: widget.controller,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              validator: widget.validator,
              onChanged: widget.onChanged,
              maxLines: widget.maxLines,
              enabled: widget.enabled,
              style: theme.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: theme.bodyLarge.override(
                  color: theme.secondaryText.withOpacity(0.6),
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color: _isFocused ? theme.primary : theme.secondaryText,
                      )
                    : null,
                suffixIcon: widget.suffixIcon != null
                    ? IconButton(
                        icon: Icon(
                          widget.suffixIcon,
                          color: theme.secondaryText,
                        ),
                        onPressed: widget.onSuffixTap,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.m,
                  vertical: AppSpacing.m,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom Sheet with modern styling
class ModernBottomSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool isDismissible;
  final double? height;

  const ModernBottomSheet({
    Key? key,
    this.title,
    required this.child,
    this.isDismissible = true,
    this.height,
  }) : super(key: key);

  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required Widget child,
    bool isDismissible = true,
    double? height,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModernBottomSheet(
        title: title,
        child: child,
        isDismissible: isDismissible,
        height: height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          topRight: Radius.circular(AppRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.primaryText.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          if (isDismissible) ...[
            SizedBox(height: AppSpacing.s),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.alternate,
                borderRadius: BorderRadius.circular(AppRadius.circular),
              ),
            ),
          ],

          // Title
          if (title != null) ...[
            SizedBox(height: AppSpacing.m),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.headlineSmall,
                    ),
                  ),
                  if (isDismissible)
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
            Divider(),
          ],

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.m),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Snackbar helper with modern styling
class ModernSnackbar {
  static void show({
    required BuildContext context,
    required String message,
    SnackbarType type = SnackbarType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = FlutterFlowTheme.of(context);

    Color backgroundColor;
    IconData icon;

    switch (type) {
      case SnackbarType.success:
        backgroundColor = theme.success;
        icon = Icons.check_circle;
        break;
      case SnackbarType.error:
        backgroundColor = theme.error;
        icon = Icons.error;
        break;
      case SnackbarType.warning:
        backgroundColor = theme.warning;
        icon = Icons.warning;
        break;
      case SnackbarType.info:
        backgroundColor = theme.info;
        icon = Icons.info;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: AppSpacing.m),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
        duration: duration,
      ),
    );
  }
}

enum SnackbarType { success, error, warning, info }

/// Loading Overlay
class LoadingOverlay {
  static void show(BuildContext context, {String? message}) {
    final theme = FlutterFlowTheme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: EdgeInsets.all(AppSpacing.l),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(AppRadius.l),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryText.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
                ),
                if (message != null) ...[
                  SizedBox(height: AppSpacing.m),
                  Text(
                    message,
                    style: theme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }
}

/// Confirmation Dialog
class ConfirmationDialog {
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDangerous = false,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.secondaryBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
        ),
        title: Text(
          title,
          style: theme.headlineSmall,
        ),
        content: Text(
          message,
          style: theme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              cancelText,
              style: theme.titleSmall.override(
                color: theme.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDangerous ? theme.error : theme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.m),
              ),
            ),
            child: Text(
              confirmText,
              style: theme.titleSmall.override(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pull to Refresh Indicator with custom styling
class ModernRefreshIndicator extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const ModernRefreshIndicator({
    Key? key,
    required this.child,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: theme.primary,
      backgroundColor: theme.secondaryBackground,
      strokeWidth: 3,
      child: child,
    );
  }
}
