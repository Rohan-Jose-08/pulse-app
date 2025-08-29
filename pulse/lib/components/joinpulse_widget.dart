import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/backend/api_service.dart';
import '/auth/base_auth_user_provider.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'joinpulse_model.dart';
export 'joinpulse_model.dart';

/// Create a **"Join Pulse"** interaction flow for the Pulse app in
/// FlutterFlow.
///
/// When a user taps the **"Join Pulse"** button on any Pulse card in the feed
/// on Home page, open a **modal bottom sheet card** or **popup dialog** that
/// shows detailed information about the selected Pulse event.
///
/// 💡 Pulse is a real-time social event app where users can join ongoing or
/// upcoming events ("Pulses") organized by other users.
///
/// 📦 Data Model Context (Prisma Schema Fields for Pulse):
/// - `title` (String)
/// - `description` (String)
/// - `eventTime` (DateTime)
/// - `location` (String or "lat,lng")
/// - `author.displayName` (String from related User)
/// - `isPublic` (Boolean)
/// - `participants` (Array of User IDs)
/// - `tags` (Array of Strings)
///
/// 🧩 Functional Components:
/// model Pulse {
///   id           String    @id @default(cuid())
///   title        String
///   description  String
///   location     String?
///   eventTime    DateTime
///   createdAt    DateTime  @default(now())
///   updatedAt    DateTime  @updatedAt
///   isPublic     Boolean   @default(true)
///   tags         String[]
///
///   // Creator of the pulse
///   authorId     String
///   author       User      @relation("CreatedPulses", fields: [authorId],
/// references: [id])
///
///   // Participants
///   participants User[]    @relation("PulseParticipants")
/// }
/// **On "Join Pulse" Button Tap**:
///    - Show a **Popup Card** (Modal Bottom Sheet or Alert Dialog)
///    - The card should display:
///      - 🧑‍💼 Host name (`author.displayName`)
///      - 📍 Location (String)
///      - 🕒 Event time (Formatted DateTime)
///      - 📝 Full Description
///      - 🏷️ Tags (if available)
///      - 👥 Number of participants (if supported)
///    - Add an animated hero transition or scale-in animation
///
///  **"Confirm Join" Button**:
///    - Add a primary button at the bottom: **“Join This Pulse”**
///    - On tap:
///      - Call backend API / Firebase Function to update the Pulse's
/// participant list, adding the current user
///      - Show a Snackbar: “You’ve joined the Pulse!”
///      - Optionally navigate to a confirmation or event detail screen
///
///  **Cancel Button**:
///    - A secondary “Cancel” or close icon (top-right) to dismiss the popup
///
/// 🧪 Optional Enhancements:
/// - Animate the map preview for location (static map image or coordinates)
/// - Add a countdown timer until `eventTime`
/// - Show profile picture of host
/// - Include a “View Full Details” link to navigate to a full event page
///
/// 🎨 Design Style:
/// - Rounded corners on the modal card (24px radius)
/// - Vibrant Pulse branding: Gradient (purple → orange)
/// - Use Google Fonts or similar with a modern sans-serif font
/// - Light and Dark mode support
/// - Ensure the popup card is scrollable for longer descriptions
///
/// 🔐 Auth Integration:
/// - Only show “Join Pulse” button if the user is logged in
/// - Automatically link the Firebase Auth UID when adding participant to the
/// backend
///
/// 📌 Backend Notes:
/// - Call a secure backend route (via REST or Firebase Functions) to:
///    - Add current user ID to the Pulse’s `participants` array
///    - Ensure no duplicates
///    - Update `updatedAt` timestamp
class JoinpulseWidget extends StatefulWidget {
  final Map<String, dynamic> pulse;
  final VoidCallback? onJoinSuccess;

  const JoinpulseWidget({
    super.key,
    required this.pulse,
    this.onJoinSuccess,
  });

  @override
  State<JoinpulseWidget> createState() => _JoinpulseWidgetState();
}

class _JoinpulseWidgetState extends State<JoinpulseWidget> {
  late JoinpulseModel _model;

  @override
  void setState(VoidCallback callback) {
    super.setState(callback);
    _model.onUpdate();
  }

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => JoinpulseModel());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.maybeDispose();

    super.dispose();
  }

  String _formatEventTime(dynamic eventTime) {
    if (eventTime == null) return 'Time TBD';

    try {
      final dateTime = DateTime.parse(eventTime.toString());
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final eventDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      String datePrefix;
      if (eventDate == today) {
        datePrefix = 'Today';
      } else if (eventDate == today.add(Duration(days: 1))) {
        datePrefix = 'Tomorrow';
      } else {
        datePrefix = '${dateTime.month}/${dateTime.day}';
      }

      final timeString =
          '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
      return '$datePrefix, $timeString';
    } catch (e) {
      return 'Time TBD';
    }
  }

  List<Widget> _buildTags() {
    final tags = List<String>.from(widget.pulse['tags'] ?? []);
    if (tags.isEmpty) return [];

    return tags
        .take(3)
        .map((tag) => Padding(
              padding: EdgeInsetsDirectional.fromSTEB(6.0, 12.0, 6.0, 12.0),
              child: Container(
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).tertiary,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(
                    color: Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    tag,
                    style: FlutterFlowTheme.of(context).labelSmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FlutterFlowTheme.of(context)
                                .labelSmall
                                .fontWeight,
                            fontStyle: FlutterFlowTheme.of(context)
                                .labelSmall
                                .fontStyle,
                          ),
                          color: Colors.white,
                          letterSpacing: 0.0,
                          fontWeight: FlutterFlowTheme.of(context)
                              .labelSmall
                              .fontWeight,
                          fontStyle:
                              FlutterFlowTheme.of(context).labelSmall.fontStyle,
                        ),
                  ),
                ),
              ),
            ))
        .toList();
  }

  bool _isCurrentUserParticipant() {
    if (currentUser?.uid == null) return false;

    final participants = widget.pulse['participants'] as List<dynamic>? ?? [];
    return participants.any((participant) =>
        participant['id'] == currentUser?.uid ||
        participant['firebaseUid'] == currentUser?.uid);
  }

  bool _isCurrentUserAuthor() {
    if (currentUser?.uid == null) return false;

    final author = widget.pulse['author'] as Map<String, dynamic>?;
    return author != null &&
        (author['id'] == currentUser?.uid ||
            author['firebaseUid'] == currentUser?.uid);
  }

  bool _canJoinPulse() {
    // Can't join if user is not logged in
    if (currentUser?.uid == null) return false;

    // Can't join if already a participant
    if (_isCurrentUserParticipant()) return false;

    // Can't join if user is the author
    if (_isCurrentUserAuthor()) return false;

    // Only can join public pulses
    return widget.pulse['isPublic'] == true;
  }

  Future<void> _joinPulse() async {
    try {
      final result = await ApiService.instance.joinPulse(widget.pulse['id']);
      if (result != null && result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully joined pulse!'),
            backgroundColor: FlutterFlowTheme.of(context).success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );

        // Call the callback to refresh data
        widget.onJoinSuccess?.call();

        // Close the modal
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join pulse. Please try again.'),
            backgroundColor: FlutterFlowTheme.of(context).error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining pulse: $e'),
          backgroundColor: FlutterFlowTheme.of(context).error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _leavePulse() async {
    try {
      final result = await ApiService.instance.leavePulse(widget.pulse['id']);
      if (result != null && result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully left pulse!'),
            backgroundColor: FlutterFlowTheme.of(context).success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );

        // Call the callback to refresh data
        widget.onJoinSuccess?.call();

        // Close the modal
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave pulse. Please try again.'),
            backgroundColor: FlutterFlowTheme.of(context).error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leaving pulse: $e'),
          backgroundColor: FlutterFlowTheme.of(context).error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(24.0, 24.0, 24.0, 24.0),
        child: Container(
          width: MediaQuery.sizeOf(context).width * 1.0,
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            boxShadow: [
              BoxShadow(
                blurRadius: 8.0,
                color: Color(0x33000000),
                offset: Offset(
                  0.0,
                  -2.0,
                ),
                spreadRadius: 0.0,
              )
            ],
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(0.0),
              bottomRight: Radius.circular(0.0),
              topLeft: Radius.circular(24.0),
              topRight: Radius.circular(24.0),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join Pulse Event',
                            style: FlutterFlowTheme.of(context)
                                .headlineMedium
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .headlineMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .headlineMedium
                                        .fontStyle,
                                  ),
                                  color:
                                      FlutterFlowTheme.of(context).primaryText,
                                  letterSpacing: 0.0,
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .headlineMedium
                                      .fontStyle,
                                ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 32.0,
                                height: 32.0,
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context).accent2,
                                  borderRadius: BorderRadius.circular(16.0),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16.0),
                                  child: Image.network(
                                    'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w0NTYyMDF8MHwxfHJhbmRvbXx8fHx8fHx8fDE3NTM5NjUwODB8&ixlib=rb-4.1.0&q=80&w=1080',
                                    width: 32.0,
                                    height: 32.0,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Text(
                                widget.pulse['author']?['displayName'] ??
                                    'Unknown Host',
                                style: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontWeight,
                                        fontStyle: FlutterFlowTheme.of(context)
                                            .bodyMedium
                                            .fontStyle,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      letterSpacing: 0.0,
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .fontStyle,
                                    ),
                              ),
                            ].divide(SizedBox(width: 8.0)),
                          ),
                        ].divide(SizedBox(height: 8.0)),
                      ),
                    ),
                    FlutterFlowIconButton(
                      borderColor: Colors.transparent,
                      borderRadius: 20.0,
                      buttonSize: 40.0,
                      fillColor: Color(0x00FFFFFF),
                      icon: Icon(
                        Icons.close_rounded,
                        color: FlutterFlowTheme.of(context).secondaryText,
                        size: 24.0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  height: 200.0,
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).accent4,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Container(
                    width: double.infinity,
                    height: 200.0,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16.0),
                          child: Image.network(
                            'https://images.unsplash.com/photo-1615725634921-baf25b7fb19a?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w0NTYyMDF8MHwxfHJhbmRvbXx8fHx8fHx8fDE3NTM5NjUwODB8&ixlib=rb-4.1.0&q=80&w=1080',
                            width: double.infinity,
                            height: 200.0,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          height: 200.0,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Color(0x66000000)],
                              stops: [0.6, 1.0],
                              begin: AlignmentDirectional(0.0, -1.0),
                              end: AlignmentDirectional(0, 1.0),
                            ),
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              16.0, 16.0, 16.0, 16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.location_on_rounded,
                                    color: Colors.white,
                                    size: 20.0,
                                  ),
                                  Text(
                                    () {
                                      final rawLoc = widget.pulse['location'];
                                      try {
                                        if (rawLoc is Map<String, dynamic>) {
                                          final name =
                                              (rawLoc['name'] as String?)
                                                  ?.trim();
                                          final city =
                                              (rawLoc['city'] as String?)
                                                  ?.trim();
                                          final country =
                                              (rawLoc['country'] as String?)
                                                  ?.trim();
                                          if (name != null && name.isNotEmpty) {
                                            final parts = [name, city]
                                                .whereType<String>()
                                                .where((e) => e.isNotEmpty)
                                                .take(2)
                                                .join(', ');
                                            if (parts.isNotEmpty) return parts;
                                          }
                                          final parts = [city, country]
                                              .whereType<String>()
                                              .where((e) => e.isNotEmpty)
                                              .toList();
                                          if (parts.isNotEmpty)
                                            return parts.join(', ');
                                          final lat = rawLoc['latitude'];
                                          final lng = rawLoc['longitude'];
                                          if (lat is num && lng is num) {
                                            return '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
                                          }
                                        } else if (rawLoc is String &&
                                            rawLoc.trim().isNotEmpty) {
                                          return rawLoc;
                                        }
                                      } catch (_) {}
                                      final lat = widget.pulse['latitude'];
                                      final lng = widget.pulse['longitude'];
                                      if (lat is num && lng is num) {
                                        return '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
                                      }
                                      return 'Location TBD';
                                    }(),
                                    style: FlutterFlowTheme.of(context)
                                        .bodyMedium
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .bodyMedium
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .bodyMedium
                                                    .fontStyle,
                                          ),
                                          color: Colors.white,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                                  .fontStyle,
                                        ),
                                  ),
                                ].divide(SizedBox(width: 8.0)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.pulse['title'] ?? 'Untitled Event',
                          style: FlutterFlowTheme.of(context)
                              .titleLarge
                              .override(
                                font: GoogleFonts.interTight(
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .titleLarge
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .titleLarge
                                      .fontStyle,
                                ),
                                color: FlutterFlowTheme.of(context).primaryText,
                                letterSpacing: 0.0,
                                fontWeight: FlutterFlowTheme.of(context)
                                    .titleLarge
                                    .fontWeight,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .titleLarge
                                    .fontStyle,
                              ),
                        ),
                        Text(
                          widget.pulse['description'] ??
                              'No description available',
                          style: FlutterFlowTheme.of(context)
                              .bodyMedium
                              .override(
                                font: GoogleFonts.inter(
                                  fontWeight: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontWeight,
                                  fontStyle: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .fontStyle,
                                ),
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                                letterSpacing: 0.0,
                                fontWeight: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontWeight,
                                fontStyle: FlutterFlowTheme.of(context)
                                    .bodyMedium
                                    .fontStyle,
                              ),
                        ),
                      ].divide(SizedBox(height: 8.0)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              8.0, 12.0, 8.0, 12.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context).accent1,
                              borderRadius: BorderRadius.circular(20.0),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    color: Colors.white,
                                    size: 16.0,
                                  ),
                                  Text(
                                    _formatEventTime(widget.pulse['eventTime']),
                                    style: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontStyle,
                                          ),
                                          color: Colors.white,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelSmall
                                                  .fontStyle,
                                        ),
                                  ),
                                ].divide(SizedBox(width: 6.0)),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              8.0, 12.0, 8.0, 12.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context).accent2,
                              borderRadius: BorderRadius.circular(20.0),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.group_rounded,
                                    color: Colors.white,
                                    size: 16.0,
                                  ),
                                  Text(
                                    '${widget.pulse['participants']?.length ?? 0} joined',
                                    style: FlutterFlowTheme.of(context)
                                        .labelSmall
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontWeight,
                                            fontStyle:
                                                FlutterFlowTheme.of(context)
                                                    .labelSmall
                                                    .fontStyle,
                                          ),
                                          color: Colors.white,
                                          letterSpacing: 0.0,
                                          fontWeight:
                                              FlutterFlowTheme.of(context)
                                                  .labelSmall
                                                  .fontWeight,
                                          fontStyle:
                                              FlutterFlowTheme.of(context)
                                                  .labelSmall
                                                  .fontStyle,
                                        ),
                                  ),
                                ].divide(SizedBox(width: 6.0)),
                              ),
                            ),
                          ),
                        ),
                      ].divide(SizedBox(width: 12.0)),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: _buildTags(),
                      ),
                    ),
                  ].divide(SizedBox(height: 16.0)),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canJoinPulse())
                      FFButtonWidget(
                        onPressed: () async {
                          await _joinPulse();
                        },
                        text: 'Join This Pulse',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 52.0,
                          padding: EdgeInsets.all(8.0),
                          iconPadding: EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).primary,
                          textStyle:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    color: Colors.white,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                          elevation: 2.0,
                          borderSide: BorderSide(
                            color: Colors.transparent,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(26.0),
                        ),
                      )
                    else if (_isCurrentUserParticipant())
                      FFButtonWidget(
                        onPressed: () async {
                          await _leavePulse();
                        },
                        text: 'Leave Pulse',
                        options: FFButtonOptions(
                          width: double.infinity,
                          height: 52.0,
                          padding: EdgeInsets.all(8.0),
                          iconPadding: EdgeInsetsDirectional.fromSTEB(
                              0.0, 0.0, 0.0, 0.0),
                          color: FlutterFlowTheme.of(context).error,
                          textStyle:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontWeight,
                                      fontStyle: FlutterFlowTheme.of(context)
                                          .titleMedium
                                          .fontStyle,
                                    ),
                                    color: Colors.white,
                                    letterSpacing: 0.0,
                                    fontWeight: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontWeight,
                                    fontStyle: FlutterFlowTheme.of(context)
                                        .titleMedium
                                        .fontStyle,
                                  ),
                          elevation: 2.0,
                          borderSide: BorderSide(
                            color: Colors.transparent,
                            width: 1.0,
                          ),
                          borderRadius: BorderRadius.circular(26.0),
                        ),
                      )
                    else if (_isCurrentUserAuthor())
                      Container(
                        width: double.infinity,
                        height: 52.0,
                        decoration: BoxDecoration(
                          color: FlutterFlowTheme.of(context)
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(26.0),
                          border: Border.all(
                            color: FlutterFlowTheme.of(context).primary,
                            width: 2.0,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person,
                                color: FlutterFlowTheme.of(context).primary,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'You Created This Pulse',
                                style: FlutterFlowTheme.of(context)
                                    .titleMedium
                                    .override(
                                      font: GoogleFonts.interTight(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 52.0,
                        decoration: BoxDecoration(
                          color: FlutterFlowTheme.of(context)
                              .secondaryText
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(26.0),
                          border: Border.all(
                            color: FlutterFlowTheme.of(context).secondaryText,
                            width: 2.0,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Login to Join',
                            style: FlutterFlowTheme.of(context)
                                .titleMedium
                                .override(
                                  font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                ),
                          ),
                        ),
                      ),
                  ].divide(SizedBox(height: 12.0)),
                ),
              ].divide(SizedBox(height: 20.0)),
            ),
          ),
        ),
      ),
    );
  }
}
