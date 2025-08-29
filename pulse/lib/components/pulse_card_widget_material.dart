import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import '../auth/firebase_auth/auth_util.dart';

class PulseCardWidgetMaterial extends StatefulWidget {
  final Map<String, dynamic> pulse;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isHighlighted;
  final bool showActions;

  const PulseCardWidgetMaterial({
    Key? key,
    required this.pulse,
    this.onTap,
    this.onLongPress,
    this.isHighlighted = false,
    this.showActions = true,
  }) : super(key: key);

  @override
  State<PulseCardWidgetMaterial> createState() =>
      _PulseCardWidgetMaterialState();
}

class _PulseCardWidgetMaterialState extends State<PulseCardWidgetMaterial> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // Add null safety check for pulse data
    if (widget.pulse.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            'Invalid pulse data',
            style: FlutterFlowTheme.of(context).bodyMedium,
          ),
        ),
      );
    }

    final imageUrl = widget.pulse['imageUrl'] as String?;
    final date = DateTime.tryParse(widget.pulse['createdAt'] ?? '');
    final formattedDate =
        date != null ? DateFormat('MMM d, yyyy').format(date) : 'No date';
    final uid = currentUserUid;
    final authorObj = widget.pulse['author'];
    final authorId = widget.pulse['authorId'];
    final bool isAuthor = (authorObj is Map &&
            (authorObj['id'] == uid || authorObj['firebaseUid'] == uid)) ||
        (authorId == uid);
    final participants = widget.pulse['participants'];
    final bool isParticipant = participants is List &&
        participants.any((p) {
          try {
            if (p is Map) return p['id'] == uid || p['firebaseUid'] == uid;
          } catch (_) {}
          return false;
        });

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      transform: Matrix4.identity()
        ..scale(_isPressed ? 0.98 : 1.0)
        ..translate(
          0.0,
          _isPressed ? 2.0 : 0.0,
          0.0,
        ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () async {
          final onTap = widget.onTap;
          if (onTap != null) {
            await Haptics.vibrate(HapticsType.light);
            onTap();
          }
        },
        onLongPress: () async {
          final onLongPress = widget.onLongPress;
          if (onLongPress != null) {
            await Haptics.vibrate(HapticsType.medium);
            onLongPress();
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isHighlighted
                ? FlutterFlowTheme.of(context).primary.withOpacity(0.05)
                : FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(24),
            border: widget.isHighlighted
                ? Border.all(
                    color:
                        FlutterFlowTheme.of(context).primary.withOpacity(0.2),
                    width: 2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: double.infinity,
                      height: 180,
                      color:
                          FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: FlutterFlowTheme.of(context)
                              .primary
                              .withOpacity(0.5),
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(imageUrl != null ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .primary
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.pulse['isPublic'] == true
                                    ? Icons.public_outlined
                                    : Icons.lock_outline,
                                size: 16,
                                color: FlutterFlowTheme.of(context).primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.pulse['isPublic'] == true
                                    ? 'Public'
                                    : 'Private',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: FlutterFlowTheme.of(context).primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formattedDate,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.pulse['title'] ?? 'Untitled Pulse',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: FlutterFlowTheme.of(context).primaryText,
                      ),
                    ),
                    if (widget.pulse['description'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.pulse['description'],
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    ...(() {
                      // Derive display location: backend may return nested location object
                      String displayLocation = '';
                      final rawLoc = widget.pulse['location'];
                      if (rawLoc is String) {
                        displayLocation = rawLoc;
                      } else if (rawLoc is Map) {
                        final name = (rawLoc['name'] ?? '').toString();
                        final city = (rawLoc['city'] ?? '').toString();
                        final country = (rawLoc['country'] ?? '').toString();
                        final parts = [name, city, country]
                            .where((e) => e.trim().isNotEmpty)
                            .toList();
                        if (parts.isNotEmpty) {
                          displayLocation = parts.take(2).join(', ');
                        } else {
                          final lat = rawLoc['latitude'];
                          final lng = rawLoc['longitude'];
                          if (lat is num && lng is num) {
                            displayLocation =
                                '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}';
                          }
                        }
                      }
                      if (displayLocation.isEmpty) return <Widget>[];
                      return <Widget>[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                displayLocation,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ];
                    })(),
                    if (widget.showActions) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  FlutterFlowTheme.of(context).primary,
                                  FlutterFlowTheme.of(context)
                                      .primary
                                      .withOpacity(0.8),
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: FlutterFlowTheme.of(context)
                                      .primary
                                      .withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                (widget.pulse['title'] ?? 'P')
                                    .toString()
                                    .characters
                                    .first
                                    .toUpperCase(),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.pulse['participants']?.length ?? 0} participants',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: FlutterFlowTheme.of(context)
                                        .primaryText,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Active',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                      ),
                                    ),
                                    if (isAuthor || isParticipant) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: FlutterFlowTheme.of(context)
                                              .success
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .success,
                                              width: 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle,
                                                size: 14,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .success),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Joined',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .success,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (widget.onLongPress != null)
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .primaryBackground,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.more_horiz,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  await Haptics.vibrate(HapticsType.light);
                                  final onLongPress = widget.onLongPress;
                                  if (onLongPress != null) {
                                    onLongPress();
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
