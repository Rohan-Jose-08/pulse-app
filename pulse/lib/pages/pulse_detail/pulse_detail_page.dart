import '/backend/api_service.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/pages/messaging/live_group_chat_page.dart';
import '/pages/edit_pulse/edit_pulse_widget.dart';
import '/pages/highlights/video_capture_page.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'pulse_detail_model.dart';
export 'pulse_detail_model.dart';

class PulseDetailPage extends StatefulWidget {
  const PulseDetailPage({
    super.key,
    required this.pulseId,
    this.initialPulse,
  });

  final String pulseId;
  final Map<String, dynamic>? initialPulse;

  static String routeName = 'PulseDetail';
  static String routePath = '/pulse/:id';

  @override
  State<PulseDetailPage> createState() => _PulseDetailPageState();
}

class _PulseDetailPageState extends State<PulseDetailPage>
    with TickerProviderStateMixin {
  late PulseDetailModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _showMap = false; // Lazy-load map toggle

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PulseDetailModel());

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Initialize data
    if (widget.initialPulse != null) {
      _model.setPulseData(widget.initialPulse);
      _model.setLoading(false);
    }

    // Fetch complete pulse data
    _loadPulseDetails();

    // Start animations
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _model.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadPulseDetails() async {
    if (widget.pulseId.isEmpty) {
      _model.setError('Invalid pulse ID');
      _model.setLoading(false);
      if (mounted) setState(() {});
      return;
    }

    try {
      _model.setLoading(true);
      _model.setError(null);
      if (mounted) setState(() {});

      final pulseData = await ApiService.instance.getPulseById(widget.pulseId);

      if (pulseData != null) {
        _model.setPulseData(pulseData);
        _model.setError(null);

        // Track pulse view for ML
        ApiService.instance.trackPulseView(widget.pulseId);
      } else {
        _model.setError('Pulse not found');
      }
    } catch (e) {
      print('Error loading pulse details: $e');
      _model.setError('Failed to load pulse details');
    } finally {
      _model.setLoading(false);
      if (mounted) setState(() {});
    }
  }

  Future<void> _joinPulse() async {
    await HapticFeedback.lightImpact();

    try {
      _model.setJoinLoading(true);
      if (mounted) setState(() {});

      final result = await ApiService.instance.joinPulse(widget.pulseId);

      if (result != null && result['success'] == true) {
        // Track join interaction for ML
        await ApiService.instance.trackPulseJoin(widget.pulseId);

        if (mounted) {
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
        }
        // Refresh pulse data
        await _loadPulseDetails();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['message'] ?? 'Failed to join pulse'),
              backgroundColor: FlutterFlowTheme.of(context).error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
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
    } finally {
      _model.setJoinLoading(false);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openGroupChat() async {
    if (widget.pulseId.isEmpty) return;
    try {
      // Get or create the pulse group chat
      final chatResult = await ApiService.instance.getPulseChat(widget.pulseId);
      print('Chat result: $chatResult'); // Debug log

      if (chatResult != null && chatResult['id'] != null) {
        final chatId = chatResult['id'].toString();
        final chatName = chatResult['name']?.toString() ??
            _model.pulseData?['title']?.toString() ??
            'Pulse Group Chat';

        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LiveGroupChatPage(
              chatId: chatId,
              groupName: chatName,
              pulseName: widget.pulseId,
              members: (chatResult['participants'] as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList(),
            ),
          ));
        }
      } else {
        print('Chat result is null or missing id: $chatResult');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(chatResult == null
                  ? 'Failed to create or access group chat'
                  : 'Group chat is not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error opening group chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening group chat: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _leavePulse() async {
    await HapticFeedback.lightImpact();

    try {
      _model.setLeaveLoading(true);
      if (mounted) setState(() {});

      final result = await ApiService.instance.leavePulse(widget.pulseId);

      if (result != null && result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully left pulse'),
              backgroundColor: FlutterFlowTheme.of(context).success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        // Refresh pulse data
        await _loadPulseDetails();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['message'] ?? 'Failed to leave pulse'),
              backgroundColor: FlutterFlowTheme.of(context).error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
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
    } finally {
      _model.setLeaveLoading(false);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        body: _model.isLoadingDetails
            ? _buildLoadingState(theme)
            : _model.errorMessage != null
                ? _buildErrorState(theme)
                : _buildContentState(theme),
        floatingActionButton:
            _model.isLoadingDetails || _model.errorMessage != null
                ? null
                : Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    width: double.infinity,
                    child: _buildActionButton(theme),
                  ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildLoadingState(FlutterFlowTheme theme) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorState(FlutterFlowTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _model.errorMessage ?? 'Something went wrong',
            style: theme.headlineSmall.copyWith(
              color: theme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FFButtonWidget(
            onPressed: () {
              _loadPulseDetails();
            },
            text: 'Retry',
            options: FFButtonOptions(
              height: 44,
              padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
              iconPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
              color: theme.primary,
              textStyle: theme.titleSmall.copyWith(
                color: Colors.white,
              ),
              elevation: 2,
              borderSide: const BorderSide(
                color: Colors.transparent,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentState(FlutterFlowTheme theme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(theme),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPulseInfo(theme),
                  const SizedBox(height: 24),
                  _buildEventDetails(theme),
                  const SizedBox(height: 24),
                  _buildParticipantsSection(theme),
                  const SizedBox(height: 24),
                  _buildLocationSection(theme),
                  const SizedBox(height: 120), // Space for action button
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(FlutterFlowTheme theme) {
    final imageUrl = _model.imageUrl;
    final hasImage = imageUrl.isNotEmpty;

    return SliverAppBar(
      expandedHeight: hasImage ? 300 : 100,
      floating: false,
      pinned: true,
      stretch: true,
      backgroundColor: theme.primaryBackground,
      leading: FlutterFlowIconButton(
        borderColor: Colors.transparent,
        borderRadius: 30,
        borderWidth: 1,
        buttonSize: 44,
        fillColor: Colors.black.withOpacity(0.6),
        icon: Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 24,
        ),
        onPressed: () async {
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
      ),
      actions: [
        // Camera button for creating video highlights
        FlutterFlowIconButton(
          borderColor: Colors.transparent,
          borderRadius: 30,
          borderWidth: 1,
          buttonSize: 44,
          fillColor: Colors.black.withOpacity(0.6),
          icon: Icon(
            Icons.videocam_rounded,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () async {
            // Check if pulse is active based on activeFrom and activeUntil
            final pulse = _model.pulseData;
            if (pulse == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Pulse data not loaded'),
                  backgroundColor: FlutterFlowTheme.of(context).error,
                ),
              );
              return;
            }

            // Parse active window
            final now = DateTime.now();
            DateTime? activeFrom;
            DateTime? activeUntil;

            if (pulse['activeFrom'] != null) {
              activeFrom = DateTime.tryParse(pulse['activeFrom'].toString());
            }
            if (pulse['activeUntil'] != null) {
              activeUntil = DateTime.tryParse(pulse['activeUntil'].toString());
            }

            // Check if pulse is currently active
            bool isActive = false;
            if (activeFrom != null) {
              // Pulse is active if we're after activeFrom
              isActive = now.isAfter(activeFrom);

              // And if activeUntil is set, we must be before it
              if (activeUntil != null) {
                isActive = isActive && now.isBefore(activeUntil);
              }
            }

            if (isActive) {
              // Navigate to video capture page
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoCapturePage(
                    pulseId: widget.pulseId,
                    pulseName: pulse['title'] ?? pulse['name'] ?? 'Pulse',
                  ),
                ),
              );

              // Reload pulse if highlight was created
              if (result == true) {
                _loadPulseDetails();
              }
            } else {
              String message =
                  'You can only create highlights during an active pulse';

              if (activeFrom != null && now.isBefore(activeFrom)) {
                final timeUntil = activeFrom.difference(now);
                if (timeUntil.inDays > 0) {
                  message =
                      'Pulse starts in ${timeUntil.inDays} day${timeUntil.inDays > 1 ? 's' : ''}';
                } else if (timeUntil.inHours > 0) {
                  message =
                      'Pulse starts in ${timeUntil.inHours} hour${timeUntil.inHours > 1 ? 's' : ''}';
                } else {
                  message =
                      'Pulse starts in ${timeUntil.inMinutes} minute${timeUntil.inMinutes > 1 ? 's' : ''}';
                }
              } else if (activeUntil != null && now.isAfter(activeUntil)) {
                message = 'This pulse has ended';
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: FlutterFlowTheme.of(context).error,
                ),
              );
            }
          },
        ),
        const SizedBox(width: 8),
        FlutterFlowIconButton(
          borderColor: Colors.transparent,
          borderRadius: 30,
          borderWidth: 1,
          buttonSize: 44,
          fillColor: Colors.black.withOpacity(0.6),
          icon: Icon(
            Icons.share_rounded,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () async {
            // TODO: Implement share functionality
          },
        ),
        const SizedBox(width: 12),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.primary.withOpacity(0.8),
                            theme.secondary.withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.primary.withOpacity(0.8),
                      theme.secondary.withOpacity(0.8),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPulseInfo(FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _model.title,
                  style: theme.headlineMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!_model.isPublic)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.warning,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock,
                        size: 16,
                        color: theme.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Private',
                        style: theme.bodySmall.copyWith(
                          color: theme.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_model.author != null) _buildAuthorInfo(theme),
          const SizedBox(height: 16),
          if (_model.description.isNotEmpty)
            Text(
              _model.description,
              style: theme.bodyLarge.copyWith(
                height: 1.5,
              ),
            ),
          const SizedBox(height: 16),
          if (_model.tags.isNotEmpty) _buildTagsSection(theme),
        ],
      ),
    );
  }

  Widget _buildAuthorInfo(FlutterFlowTheme theme) {
    final author = _model.author!;
    final authorName = author['displayName'] ?? 'Unknown User';
    final authorImage = author['profileImageUrl'] ?? '';

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.alternate,
          backgroundImage:
              authorImage.isNotEmpty ? NetworkImage(authorImage) : null,
          child: authorImage.isEmpty
              ? Icon(
                  Icons.person,
                  color: theme.primaryText,
                  size: 20,
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hosted by',
                style: theme.labelSmall.copyWith(
                  color: theme.secondaryText,
                ),
              ),
              Text(
                authorName,
                style: theme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_model.isAuthor)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: theme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.primary,
                width: 1,
              ),
            ),
            child: Text(
              'Host',
              style: theme.bodySmall.copyWith(
                color: theme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTagsSection(FlutterFlowTheme theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _model.tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: theme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            '#$tag',
            style: theme.bodySmall.copyWith(
              color: theme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEventDetails(FlutterFlowTheme theme) {
    final eventTime = _model.eventTime;
    final derivedLoc = _model.locationLabelDerived;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Event Details',
                style: theme.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (eventTime != null) ...[
                _buildDetailRow(
                  theme,
                  Icons.access_time,
                  'Date & Time',
                  '${DateFormat('MMM dd, yyyy').format(eventTime)} at ${DateFormat('h:mm a').format(eventTime)}',
                ),
                const SizedBox(height: 12),
              ],
              _buildDetailRow(
                theme,
                Icons.location_on,
                'Location',
                derivedLoc.isNotEmpty ? derivedLoc : 'Location TBD',
              ),
              const SizedBox(height: 12),
              _buildDetailRow(
                theme,
                Icons.people,
                'Participants',
                _model.maxParticipants != null
                    ? '${_model.totalParticipants}/${_model.maxParticipants}'
                    : '${_model.totalParticipants} going',
              ),
              if (_model.isFullyBooked) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.warning,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Event is fully booked',
                      style: theme.bodySmall.copyWith(
                        color: theme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    FlutterFlowTheme theme,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.labelMedium.copyWith(
                  color: theme.secondaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.bodyMedium.copyWith(
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsSection(FlutterFlowTheme theme) {
    if (_model.participants.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Participants (${_model.participants.length})',
                    style: theme.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_model.participants.length > 3)
                    TextButton(
                      onPressed: () {
                        // TODO: Show all participants
                      },
                      child: Text(
                        'View All',
                        style: theme.bodySmall.copyWith(
                          color: theme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ...(_model.participants.take(3).map((participant) {
                return _buildParticipantTile(theme, participant);
              }).toList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantTile(
      FlutterFlowTheme theme, Map<String, dynamic> participant) {
    final name = participant['displayName'] ?? 'Unknown User';
    final imageUrl = participant['profileImageUrl'] ?? '';
    final isAuthor = participant['isAuthor'] ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.alternate,
            backgroundImage:
                imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            child: imageUrl.isEmpty
                ? Icon(
                    Icons.person,
                    color: theme.primaryText,
                    size: 20,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: theme.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isAuthor)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.primary,
                  width: 1,
                ),
              ),
              child: Text(
                'Host',
                style: theme.bodySmall.copyWith(
                  color: theme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(FlutterFlowTheme theme) {
    final derivedLoc = _model.locationLabelDerived;
    if (derivedLoc.isEmpty) return const SizedBox.shrink();
    final lat = _model.latitude;
    final lng = _model.longitude;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location',
                style: theme.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: theme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      derivedLoc,
                      style: theme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (_model.street.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                        width: 32), // align with text after icon space
                    Expanded(
                      child: Text(
                        _model.street,
                        style: theme.bodySmall.copyWith(
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              // Lazy map: show button first; instantiate GoogleMap only after user action
              if (lat != null && lng != null)
                (!_showMap
                    ? GestureDetector(
                        onTap: () {
                          setState(() => _showMap = true);
                        },
                        child: Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: theme.alternate,
                            gradient: LinearGradient(
                              colors: [
                                theme.primary.withOpacity(0.15),
                                theme.secondary.withOpacity(0.15),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map_outlined,
                                    size: 42, color: theme.primary),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to load map',
                                  style: theme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.primary,
                                  ),
                                ),
                                Text(
                                  '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}',
                                  style: theme.bodySmall.copyWith(
                                    color: theme.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: gmaps.GoogleMap(
                            initialCameraPosition: gmaps.CameraPosition(
                              target: gmaps.LatLng(lat, lng),
                              zoom: 14.5,
                            ),
                            compassEnabled: false,
                            mapToolbarEnabled: false,
                            tiltGesturesEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            markers: {
                              gmaps.Marker(
                                markerId:
                                    const gmaps.MarkerId('pulse_location'),
                                position: gmaps.LatLng(lat, lng),
                                infoWindow:
                                    gmaps.InfoWindow(title: _model.title),
                              ),
                            },
                            onMapCreated: (_) {
                              // Future: apply custom map style
                            },
                          ),
                        ),
                      ))
              else
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.alternate,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.map,
                          size: 48,
                          color: theme.secondaryText,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Location map not available',
                          style: theme.bodySmall.copyWith(
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(FlutterFlowTheme theme) {
    if (_model.isAuthor) {
      return FFButtonWidget(
        onPressed: () {
          final current = _model.pulseData ?? {};
          context.pushNamed(
            EditPulseWidget.routeName,
            pathParameters: {'id': widget.pulseId},
            extra: {'pulse': current},
          ).then((value) {
            if (value is Map<String, dynamic>) {
              _model.setPulseData(value);
              setState(() {});
            } else {
              // Optionally reload from backend if we got no result
              _loadPulseDetails();
            }
          });
        },
        text: 'Edit Pulse',
        icon: Icon(
          Icons.edit,
          size: 20,
        ),
        options: FFButtonOptions(
          width: double.infinity,
          height: 54,
          padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
          iconPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
          color: theme.secondary,
          textStyle: theme.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          elevation: 3,
          borderSide: const BorderSide(
            color: Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(27),
        ),
      );
    } else if (_model.isParticipant) {
      return Row(
        children: [
          // Group Chat Button
          Expanded(
            child: FFButtonWidget(
              onPressed: _openGroupChat,
              text: 'Group Chat',
              icon: Icon(
                Icons.group_rounded,
                size: 20,
              ),
              options: FFButtonOptions(
                height: 54,
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                iconPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                color: theme.primary,
                textStyle: theme.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                elevation: 3,
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(27),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Leave Button
          Expanded(
            child: FFButtonWidget(
              onPressed: _model.isLeaving ? null : _leavePulse,
              text: _model.isLeaving ? 'Leaving...' : 'Leave',
              icon: Icon(
                Icons.exit_to_app,
                size: 20,
              ),
              options: FFButtonOptions(
                height: 54,
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                iconPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
                color: theme.error,
                textStyle: theme.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                elevation: 3,
                borderSide: const BorderSide(
                  color: Colors.transparent,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(27),
                disabledColor: theme.error.withOpacity(0.6),
                disabledTextColor: Colors.white70,
              ),
            ),
          ),
        ],
      );
    } else if (_model.canJoin) {
      return FFButtonWidget(
        onPressed: _model.isJoining ? null : _joinPulse,
        text: _model.isJoining ? 'Joining...' : 'Join Pulse',
        icon: Icon(
          Icons.add,
          size: 20,
        ),
        options: FFButtonOptions(
          width: double.infinity,
          height: 54,
          padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
          iconPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
          color: theme.primary,
          textStyle: theme.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          elevation: 3,
          borderSide: const BorderSide(
            color: Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(27),
          disabledColor: theme.primary.withOpacity(0.6),
          disabledTextColor: Colors.white70,
        ),
      );
    } else {
      String buttonText = 'Cannot Join';
      if (_model.isFullyBooked) {
        buttonText = 'Fully Booked';
      } else if (!_model.isPublic) {
        buttonText = 'Private Event';
      }

      return FFButtonWidget(
        onPressed: null,
        text: buttonText,
        icon: Icon(
          Icons.block,
          size: 20,
        ),
        options: FFButtonOptions(
          width: double.infinity,
          height: 54,
          padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
          iconPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 0),
          color: theme.secondaryText.withOpacity(0.3),
          textStyle: theme.titleMedium.copyWith(
            color: theme.secondaryText,
            fontWeight: FontWeight.w600,
          ),
          elevation: 0,
          borderSide: BorderSide(
            color: theme.secondaryText.withOpacity(0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(27),
        ),
      );
    }
  }
}
