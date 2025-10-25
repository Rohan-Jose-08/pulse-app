import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import 'enhanced_ui_components.dart';
import '../utils/animations.dart';

/// Enhanced Pulse Card for displaying pulse items
class EnhancedPulseCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? location;
  final int? participantCount;
  final bool isActive;
  final bool isNearby;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;
  final Widget? trailing;

  const EnhancedPulseCard({
    Key? key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.location,
    this.participantCount,
    this.isActive = false,
    this.isNearby = false,
    this.onTap,
    this.onJoin,
    this.trailing,
  }) : super(key: key);

  @override
  State<EnhancedPulseCard> createState() => _EnhancedPulseCardState();
}

class _EnhancedPulseCardState extends State<EnhancedPulseCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AppAnimation.fast,
        curve: AppAnimation.emphasized,
        transform: Matrix4.identity()..translate(0.0, _isHovered ? -4.0 : 0.0),
        child: ModernCard(
          elevation: _isHovered ? AppElevation.high : AppElevation.medium,
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Header (if available)
              if (widget.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.l),
                    topRight: Radius.circular(AppRadius.l),
                  ),
                  child: Stack(
                    children: [
                      Image.network(
                        widget.imageUrl!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [theme.primary, theme.secondary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(
                              Icons.image,
                              size: 64,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          );
                        },
                      ),
                      // Status badge overlay
                      if (widget.isActive)
                        Positioned(
                          top: AppSpacing.m,
                          right: AppSpacing.m,
                          child: PulseAnimation(
                            pulseColor: theme.success,
                            child: StatusBadge(
                              text: 'Active',
                              color: theme.success,
                              icon: Icons.circle,
                              isPulsing: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.m),
              ],

              // Content
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: theme.titleLarge.override(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.trailing != null) ...[
                          SizedBox(width: AppSpacing.s),
                          widget.trailing!,
                        ],
                      ],
                    ),

                    // Subtitle
                    if (widget.subtitle != null) ...[
                      SizedBox(height: AppSpacing.s),
                      Text(
                        widget.subtitle!,
                        style: theme.bodyMedium.override(
                          color: theme.secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    SizedBox(height: AppSpacing.m),

                    // Info Row
                    Row(
                      children: [
                        // Location
                        if (widget.location != null) ...[
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: theme.secondaryText,
                          ),
                          SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              widget.location!,
                              style: theme.labelSmall.override(
                                color: theme.secondaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],

                        // Participant count
                        if (widget.participantCount != null) ...[
                          if (widget.location != null)
                            SizedBox(width: AppSpacing.m),
                          Icon(
                            Icons.people,
                            size: 16,
                            color: theme.secondaryText,
                          ),
                          SizedBox(width: AppSpacing.xs),
                          Text(
                            '${widget.participantCount}',
                            style: theme.labelSmall.override(
                              color: theme.secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],

                        // Nearby indicator
                        if (widget.isNearby) ...[
                          SizedBox(width: AppSpacing.m),
                          StatusBadge(
                            text: 'Nearby',
                            color: theme.tertiary,
                            icon: Icons.near_me,
                          ),
                        ],
                      ],
                    ),

                    // Join Button
                    if (widget.onJoin != null) ...[
                      SizedBox(height: AppSpacing.m),
                      SizedBox(
                        width: double.infinity,
                        child: GradientButton(
                          text: 'Join Pulse',
                          icon: Icons.login,
                          onPressed: widget.onJoin,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(height: AppSpacing.m),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enhanced Message Bubble
class MessageBubble extends StatelessWidget {
  final String message;
  final bool isSent;
  final String? timestamp;
  final bool showAvatar;
  final String? avatarUrl;
  final bool isRead;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isSent,
    this.timestamp,
    this.showAvatar = true,
    this.avatarUrl,
    this.isRead = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return SlideInFromBottom(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisAlignment:
              isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for received messages
            if (!isSent && showAvatar)
              Padding(
                padding: EdgeInsets.only(right: AppSpacing.s),
                child: PulseAvatar(
                  imageUrl: avatarUrl,
                  size: 32,
                ),
              ),

            // Message container
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.m,
                  vertical: AppSpacing.s,
                ),
                decoration: BoxDecoration(
                  gradient: isSent
                      ? LinearGradient(
                          colors: [theme.primary, theme.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSent ? null : theme.alternate.withOpacity(0.3),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.l),
                    topRight: Radius.circular(AppRadius.l),
                    bottomLeft:
                        Radius.circular(isSent ? AppRadius.l : AppRadius.xs),
                    bottomRight:
                        Radius.circular(isSent ? AppRadius.xs : AppRadius.l),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primaryText.withOpacity(0.05),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: theme.bodyMedium.override(
                        color: isSent ? Colors.white : theme.primaryText,
                      ),
                    ),
                    if (timestamp != null) ...[
                      SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timestamp!,
                            style: theme.labelSmall.override(
                              color: isSent
                                  ? Colors.white.withOpacity(0.7)
                                  : theme.secondaryText,
                              fontSize: 10,
                            ),
                          ),
                          if (isSent) ...[
                            SizedBox(width: AppSpacing.xs),
                            Icon(
                              isRead ? Icons.done_all : Icons.done,
                              size: 14,
                              color: isRead
                                  ? theme.info
                                  : Colors.white.withOpacity(0.7),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Spacing for sent messages
            if (isSent && showAvatar) SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

/// Enhanced Empty State
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    Key? key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox,
    this.actionText,
    this.onAction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return ScaleInAnimation(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with gradient background
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.primary.withOpacity(0.2),
                      theme.secondary.withOpacity(0.2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 64,
                  color: theme.primary,
                ),
              ),

              SizedBox(height: AppSpacing.l),

              // Title
              Text(
                title,
                style: theme.headlineSmall,
                textAlign: TextAlign.center,
              ),

              SizedBox(height: AppSpacing.s),

              // Message
              Text(
                message,
                style: theme.bodyMedium.override(
                  color: theme.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),

              // Action button
              if (actionText != null && onAction != null) ...[
                SizedBox(height: AppSpacing.l),
                GradientButton(
                  text: actionText!,
                  onPressed: onAction,
                  icon: Icons.add,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
