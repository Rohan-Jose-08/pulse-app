import 'package:flutter/material.dart';
import '../../services/moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Banner that displays the user's current moderation status
/// Shows warnings, mutes, or suspensions if active
class ModerationStatusBanner extends StatefulWidget {
  final VoidCallback? onTap;

  const ModerationStatusBanner({super.key, this.onTap});

  @override
  State<ModerationStatusBanner> createState() => _ModerationStatusBannerState();
}

class _ModerationStatusBannerState extends State<ModerationStatusBanner> {
  final ModerationService _moderationService = ModerationService.instance;

  UserModerationStatus? _status;
  bool _isLoading = true;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _moderationService.getMyModerationStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isDismissed || _status == null) {
      return const SizedBox.shrink();
    }

    // Only show banner if user has active restrictions
    if (!_status!.hasRestrictions && _status!.warningCount == 0) {
      return const SizedBox.shrink();
    }

    return _buildBanner(context);
  }

  Widget _buildBanner(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bannerConfig = _getBannerConfig();

    return GestureDetector(
      onTap: widget.onTap ?? () => _showStatusDetails(context),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bannerConfig.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bannerConfig.color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bannerConfig.color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                bannerConfig.icon,
                color: bannerConfig.color,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bannerConfig.title,
                    style: theme.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                      color: bannerConfig.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bannerConfig.message,
                    style: theme.bodySmall.copyWith(
                      color: theme.primaryText.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _isDismissed = true),
              icon: Icon(
                Icons.close_rounded,
                color: theme.secondaryText,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({IconData icon, Color color, String title, String message})
      _getBannerConfig() {
    if (_status!.isBanned) {
      return (
        icon: Icons.block_rounded,
        color: Colors.red.shade800,
        title: 'Account Banned',
        message:
            _status!.banReason ?? 'Your account has been permanently banned.',
      );
    }
    if (_status!.isSuspended) {
      return (
        icon: Icons.person_off_rounded,
        color: Colors.red,
        title: 'Account Suspended',
        message: _status!.suspendedUntil != null
            ? 'Suspended until ${_formatDate(_status!.suspendedUntil!)}'
            : _status!.suspendReason ??
                'Your account is temporarily suspended.',
      );
    }
    if (_status!.isMuted) {
      return (
        icon: Icons.volume_off_rounded,
        color: Colors.orange,
        title: 'Account Muted',
        message: _status!.mutedUntil != null
            ? 'Muted until ${_formatDate(_status!.mutedUntil!)}'
            : _status!.muteReason ?? 'You cannot post or comment temporarily.',
      );
    }
    if (_status!.warningCount > 0) {
      return (
        icon: Icons.warning_rounded,
        color: Colors.amber,
        title: 'Active Warning',
        message: 'You have ${_status!.warningCount} active warning(s).',
      );
    }
    return (
      icon: Icons.info_outline_rounded,
      color: Colors.blue,
      title: 'Notice',
      message: 'Tap to view your moderation status.',
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showStatusDetails(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.alternate,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Your Moderation Status',
              style: theme.titleLarge.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Status Details
            _buildDetailRow('Status', _getCurrentStatus(), theme),
            _buildDetailRow(
              'Active Warnings',
              _status!.warningCount.toString(),
              theme,
            ),
            _buildDetailRow(
              'Can Create Pulses',
              _status!.canCreatePulses ? 'Yes' : 'No',
              theme,
            ),
            _buildDetailRow(
              'Can Send Messages',
              _status!.canSendMessages ? 'Yes' : 'No',
              theme,
            ),
            if (_status!.mutedUntil != null)
              _buildDetailRow(
                'Muted Until',
                _formatDate(_status!.mutedUntil!),
                theme,
              ),
            if (_status!.suspendedUntil != null)
              _buildDetailRow(
                'Suspended Until',
                _formatDate(_status!.suspendedUntil!),
                theme,
              ),

            const SizedBox(height: 24),

            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  String _getCurrentStatus() {
    if (_status!.isBanned) return 'Banned';
    if (_status!.isSuspended) return 'Suspended';
    if (_status!.isMuted) return 'Muted';
    if (_status!.warningCount > 0) return 'Warned';
    return 'Good Standing';
  }

  Widget _buildDetailRow(String label, String value, FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.bodyMedium.copyWith(color: theme.secondaryText),
          ),
          Text(
            value,
            style: theme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Widget to check if user can perform an action based on moderation status
class ModerationGate extends StatelessWidget {
  final Widget child;
  final Widget? blockedWidget;
  final bool checkPosting;
  final bool checkMessaging;

  const ModerationGate({
    super.key,
    required this.child,
    this.blockedWidget,
    this.checkPosting = false,
    this.checkMessaging = false,
  });

  @override
  Widget build(BuildContext context) {
    final moderationService = ModerationService.instance;

    return FutureBuilder<UserModerationStatus?>(
      future: moderationService.getMyModerationStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return child;
        }

        final status = snapshot.data!;

        // Check if action is blocked
        final isBlocked = _isActionBlocked(status);

        if (isBlocked) {
          return blockedWidget ?? _buildBlockedWidget(context, status);
        }

        return child;
      },
    );
  }

  bool _isActionBlocked(UserModerationStatus status) {
    if (status.isBanned || status.isSuspended) {
      return true;
    }

    if (checkPosting && status.isMuted) {
      return true;
    }

    if (checkMessaging && (status.isMuted || status.isSuspended)) {
      return true;
    }

    return false;
  }

  Widget _buildBlockedWidget(
      BuildContext context, UserModerationStatus status) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, color: theme.error, size: 32),
          const SizedBox(height: 8),
          Text(
            _getBlockedMessage(status),
            style: theme.bodyMedium.copyWith(color: theme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getBlockedMessage(UserModerationStatus status) {
    if (status.isBanned) {
      return status.banReason ?? 'Your account has been banned.';
    }
    if (status.isSuspended) {
      return status.suspendReason ?? 'Your account is suspended.';
    }
    if (status.isMuted) {
      return status.muteReason ??
          'You are currently muted and cannot perform this action.';
    }
    return 'This action is not available.';
  }
}

/// Helper extension for content with moderation indicators
extension ModerationIndicators on Widget {
  Widget withModerationIndicator({
    bool isHidden = false,
    bool isFlagged = false,
    bool isRemoved = false,
  }) {
    if (!isHidden && !isFlagged && !isRemoved) {
      return this;
    }

    return Stack(
      children: [
        if (isHidden || isRemoved) Opacity(opacity: 0.5, child: this) else this,
        if (isFlagged)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    'Flagged',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isHidden)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_off_rounded,
                      size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    'Hidden',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
