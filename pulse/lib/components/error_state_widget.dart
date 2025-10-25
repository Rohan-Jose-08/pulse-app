import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../flutter_flow/flutter_flow_widgets.dart';

/// Consistent error state widget with friendly messages and retry action
class ErrorStateWidget extends StatelessWidget {
  final String? title;
  final String? message;
  final IconData? icon;
  final VoidCallback? onRetry;
  final String? retryButtonText;

  const ErrorStateWidget({
    Key? key,
    this.title,
    this.message,
    this.icon,
    this.onRetry,
    this.retryButtonText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.error_outline_rounded,
              size: 80,
              color: theme.error.withOpacity(0.6),
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 24),
            Text(
              title ?? 'Oops!',
              style: theme.headlineMedium.override(
                fontWeight: FontWeight.w700,
                color: theme.primaryText,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms).slideY(
                  begin: 0.2,
                  end: 0,
                  duration: 400.ms,
                ),
            const SizedBox(height: 12),
            Text(
              message ?? 'Something went wrong. Please try again.',
              style: theme.bodyLarge.override(
                color: theme.secondaryText,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms).slideY(
                  begin: 0.2,
                  end: 0,
                  duration: 400.ms,
                ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              FFButtonWidget(
                onPressed: onRetry,
                text: retryButtonText ?? 'Try Again',
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                ),
                options: FFButtonOptions(
                  height: 48,
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
                  color: theme.primary,
                  textStyle: theme.titleSmall.override(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(24),
                ),
              ).animate().fadeIn(delay: 400.ms).scale(
                    duration: 300.ms,
                    curve: Curves.easeOutBack,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Network error specific widget
class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorWidget({Key? key, this.onRetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ErrorStateWidget(
      title: 'No Connection',
      message: 'Check your internet connection and try again.',
      icon: Icons.wifi_off_rounded,
      onRetry: onRetry,
    );
  }
}

/// Empty state widget for when no data is available
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final VoidCallback? onAction;
  final String? actionText;

  const EmptyStateWidget({
    Key? key,
    required this.title,
    required this.message,
    this.icon,
    this.onAction,
    this.actionText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.inbox_rounded,
              size: 80,
              color: theme.secondaryText.withOpacity(0.4),
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.headlineMedium.override(
                fontWeight: FontWeight.w600,
                color: theme.primaryText,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms).slideY(
                  begin: 0.2,
                  end: 0,
                  duration: 400.ms,
                ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.bodyLarge.override(
                color: theme.secondaryText,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms).slideY(
                  begin: 0.2,
                  end: 0,
                  duration: 400.ms,
                ),
            if (onAction != null && actionText != null) ...[
              const SizedBox(height: 32),
              FFButtonWidget(
                onPressed: onAction,
                text: actionText!,
                options: FFButtonOptions(
                  height: 48,
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
                  color: theme.primary,
                  textStyle: theme.titleSmall.override(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(24),
                ),
              ).animate().fadeIn(delay: 400.ms).scale(
                    duration: 300.ms,
                    curve: Curves.easeOutBack,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
