import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:google_fonts/google_fonts.dart';
import '/utils/location_formatter_new.dart';

class PulseCardWidget extends StatelessWidget {
  final Map<String, dynamic> pulse;
  final VoidCallback onJoinPressed;

  const PulseCardWidget({
    super.key,
    required this.pulse,
    required this.onJoinPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Helpers
    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // Extract & normalize fields
    final title = pulse['title'] ?? 'Untitled Event';
    // final isPublic = pulse['isPublic'] ?? true; // unused currently; retain if needed for future display
    // Structured location object now expected from backend
    final locationObj = pulse['location'];
    double? latitude = _toDouble(pulse['latitude']);
    double? longitude = _toDouble(pulse['longitude']);
    if (locationObj is Map<String, dynamic>) {
      final lat = locationObj['latitude'];
      final lng = locationObj['longitude'];
      if (lat is num && lng is num) {
        latitude = lat.toDouble();
        longitude = lng.toDouble();
      }
    }
    final distanceKm = _toDouble(pulse['distanceKm']);
    final eventTime = pulse['eventTime'] != null
        ? DateTime.parse(pulse['eventTime'])
        : DateTime.now();
    DateTime? activeFrom;
    DateTime? activeUntil;
    try {
      if (pulse['activeFrom'] is String) {
        activeFrom = DateTime.tryParse(pulse['activeFrom']);
      }
      if (pulse['activeUntil'] is String) {
        activeUntil = DateTime.tryParse(pulse['activeUntil']);
      }
    } catch (_) {}
    final bool isActive = pulse['isActive'] == true ||
        (() {
          final now = DateTime.now();
          if (activeFrom != null && activeFrom.isAfter(now)) return false;
          if (activeUntil != null && activeUntil.isBefore(now)) return false;
          return true;
        })();
    final tags = List<String>.from(pulse['tags'] ?? []);
    final primaryTag = tags.isNotEmpty ? tags[0] : 'Event';
    const maxTagsToShow = 4;
    final tagsToShow =
        tags.length > maxTagsToShow ? tags.sublist(0, maxTagsToShow) : tags;
    final remainingTagCount = tags.length - tagsToShow.length;
    final formattedTime =
        '${eventTime.hour}:${eventTime.minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        boxShadow: [
          BoxShadow(
            blurRadius: 6.0,
            color: const Color(0x1A000000),
            offset: const Offset(0.0, 2.0),
          )
        ],
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    width: 80.0,
                    height: 80.0,
                    color: FlutterFlowTheme.of(context).primary,
                    child: pulse['imageUrl'] != null &&
                            pulse['imageUrl'].toString().isNotEmpty
                        ? Image.network(
                            pulse['imageUrl'],
                            fit: BoxFit.cover,
                            width: 80.0,
                            height: 80.0,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                _getCategoryIcon(primaryTag),
                                color: Colors.white,
                                size: 40.0,
                              );
                            },
                          )
                        : Icon(
                            _getCategoryIcon(primaryTag),
                            color: Colors.white,
                            size: 40.0,
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Text(
                                distanceKm != null
                                    ? _formatDistance(distanceKm)
                                    : (latitude != null && longitude != null
                                        ? '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}'
                                        : '—'),
                                style: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.info_outline,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                  size: 20.0,
                                ),
                                onPressed: () {
                                  _showPulseDetails(context, pulse);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: FlutterFlowTheme.of(context)
                                  .titleMedium
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .primaryText,
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildActiveBadge(
                              context, isActive, activeFrom, activeUntil),
                        ],
                      ),
                      // Tags display - moved to more prominent location
                      if (tagsToShow.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Wrap(
                            spacing: 8.0,
                            runSpacing: 4.0,
                            children: [
                              ...tagsToShow.map((tag) => Container(
                                    decoration: BoxDecoration(
                                      color: FlutterFlowTheme.of(context)
                                          .primaryBackground,
                                      borderRadius: BorderRadius.circular(12.0),
                                      border: Border.all(
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        width: 1.0,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 4.0,
                                    ),
                                    child: Text(
                                      tag,
                                      style: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w500,
                                            ),
                                            color: FlutterFlowTheme.of(context)
                                                .primary,
                                            fontSize: 12.0,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  )),
                              if (remainingTagCount > 0)
                                Container(
                                  decoration: BoxDecoration(
                                    color: FlutterFlowTheme.of(context)
                                        .primaryBackground,
                                    borderRadius: BorderRadius.circular(12.0),
                                    border: Border.all(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      width: 1.0,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                    vertical: 4.0,
                                  ),
                                  child: Text(
                                    '+$remainingTagCount more',
                                    style: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .override(
                                          font: GoogleFonts.inter(
                                            fontWeight: FontWeight.w500,
                                          ),
                                          color: FlutterFlowTheme.of(context)
                                              .primary,
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            color: FlutterFlowTheme.of(context).secondaryText,
                            size: 14.0,
                          ),
                          Text(
                            formattedTime,
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ].divide(const SizedBox(width: 4.0)),
                      ),
                      Builder(builder: (context) {
                        // Backend now returns structured location object (pulse['location']) or may omit
                        final rawLoc = pulse['location'];
                        String shortLoc = 'Location N/A';
                        if (rawLoc is Map<String, dynamic>) {
                          final name = (rawLoc['name'] as String?)?.trim();
                          final city = (rawLoc['city'] as String?)?.trim();
                          final country =
                              (rawLoc['country'] as String?)?.trim();
                          if (name != null && name.isNotEmpty) {
                            shortLoc = [name, city]
                                .whereType<String>()
                                .where((e) => e.isNotEmpty)
                                .take(2)
                                .join(', ');
                          } else if ((city != null && city.isNotEmpty) ||
                              (country != null && country.isNotEmpty)) {
                            shortLoc = [city, country]
                                .whereType<String>()
                                .where((e) => e.isNotEmpty)
                                .join(', ');
                          } else if (rawLoc['latitude'] is num &&
                              rawLoc['longitude'] is num) {
                            shortLoc =
                                '${(rawLoc['latitude'] as num).toStringAsFixed(3)},${(rawLoc['longitude'] as num).toStringAsFixed(3)}';
                          }
                        } else if (rawLoc is String && rawLoc.isNotEmpty) {
                          shortLoc = rawLoc.split(',').first.trim();
                        } else if (latitude != null && longitude != null) {
                          shortLoc =
                              '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              color: FlutterFlowTheme.of(context).secondaryText,
                              size: 14.0,
                            ),
                            Text(
                              shortLoc,
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ].divide(const SizedBox(width: 4.0)),
                        );
                      }),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Container(
                                width: 24.0,
                                height: 24.0,
                                clipBehavior: Clip.antiAlias,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                child: Container(
                                  color: Colors.grey,
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 16.0,
                                  ),
                                ),
                              ),
                              Container(
                                width: 24.0,
                                height: 24.0,
                                clipBehavior: Clip.antiAlias,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                child: Container(
                                  color: Colors.grey,
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 16.0,
                                  ),
                                ),
                              ),
                              Container(
                                width: 24.0,
                                height: 24.0,
                                clipBehavior: Clip.antiAlias,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                ),
                                child: Container(
                                  color: Colors.grey,
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 16.0,
                                  ),
                                ),
                              ),
                              Container(
                                width: 24.0,
                                height: 24.0,
                                decoration: BoxDecoration(
                                  color: _getCategoryColor(primaryTag)
                                      .withOpacity(0.3),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.0,
                                  ),
                                ),
                                child: Align(
                                  alignment: AlignmentDirectional(0.0, 0.0),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      '+5',
                                      style: FlutterFlowTheme.of(context)
                                          .bodySmall
                                          .override(
                                            font: GoogleFonts.inter(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            color: Colors.white,
                                            fontSize: 10.0,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ].divide(const SizedBox(width: 0)),
                          ),
                          ElevatedButton(
                            onPressed: onJoinPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _getCategoryColor(primaryTag),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              elevation: 0.0,
                            ),
                            child: Text(
                              'Join Pulse',
                              style: FlutterFlowTheme.of(context)
                                  .titleSmall
                                  .override(
                                    font: GoogleFonts.interTight(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    color: Colors.white,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ].divide(const SizedBox(height: 6.0)),
                  ),
                ),
              ].divide(const SizedBox(width: 12.0)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPulseDetails(BuildContext context, Map<String, dynamic> pulse) {
    final title = pulse['title'] ?? 'Untitled Event';
    final description = pulse['description'] ?? '';
    // Legacy location string or label (now may be structured object). Accept both.
    String? locLabel;
    final rawLocForDetails = pulse['location'];
    if (rawLocForDetails is String) {
      locLabel = rawLocForDetails;
    } else if (rawLocForDetails is Map<String, dynamic>) {
      final name = (rawLocForDetails['name'] as String?)?.trim();
      final city = (rawLocForDetails['city'] as String?)?.trim();
      final country = (rawLocForDetails['country'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        locLabel = [name, city]
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .take(2)
            .join(', ');
      } else if ((city != null && city.isNotEmpty) ||
          (country != null && country.isNotEmpty)) {
        locLabel = [city, country]
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .join(', ');
      }
    }
    // Structured location
    final locObj = pulse['location'];
    double? derivedLat;
    double? derivedLng;
    if (locObj is Map<String, dynamic>) {
      final lat = locObj['latitude'];
      final lng = locObj['longitude'];
      if (lat is num && lng is num) {
        derivedLat = lat.toDouble();
        derivedLng = lng.toDouble();
      }
    } else {
      if (pulse['latitude'] is num)
        derivedLat = (pulse['latitude'] as num).toDouble();
      if (pulse['longitude'] is num)
        derivedLng = (pulse['longitude'] as num).toDouble();
    }
    final location = () {
      if (locLabel != null && locLabel.isNotEmpty) return locLabel;
      if (locObj is Map<String, dynamic>) {
        final name = (locObj['name'] as String?) ?? '';
        final city = (locObj['city'] as String?) ?? '';
        final country = (locObj['country'] as String?) ?? '';
        if (name.isNotEmpty)
          return [name, city].where((e) => e.isNotEmpty).take(2).join(', ');
        if (city.isNotEmpty || country.isNotEmpty)
          return [city, country].where((e) => e.isNotEmpty).join(', ');
      }
      if (derivedLat != null && derivedLng != null) {
        return LocationFormatter.formatLocation(
            latitude: derivedLat, longitude: derivedLng);
      }
      return 'Location not specified';
    }();
    final eventTime = pulse['eventTime'] != null
        ? DateTime.parse(pulse['eventTime'])
        : DateTime.now();
    final tags = List<String>.from(pulse['tags'] ?? []);
    final isPublic = pulse['isPublic'] ?? true;
    final author = pulse['author'] ?? {};
    final participants =
        List<Map<String, dynamic>>.from(pulse['participants'] ?? []);

    // Format time
    final formattedDate =
        '${eventTime.month}/${eventTime.day}/${eventTime.year}';
    final formattedTime =
        '${eventTime.hour}:${eventTime.minute.toString().padLeft(2, '0')}';

    // Get author name
    final authorName =
        author['displayName'] ?? author['email'] ?? 'Unknown User';

    // Get participant count
    final participantCount = participants.length;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          content: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image at the top if available
                if (pulse['imageUrl'] != null &&
                    pulse['imageUrl'].toString().isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.network(
                      pulse['imageUrl'],
                      fit: BoxFit.cover,
                      height: 200.0,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Container();
                      },
                    ),
                  ),
                  const SizedBox(height: 16.0),
                ],
                // Header with title and close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: FlutterFlowTheme.of(context).titleLarge.override(
                              font: GoogleFonts.interTight(
                                fontWeight: FontWeight.bold,
                              ),
                              color: FlutterFlowTheme.of(context).primaryText,
                              fontSize: 20.0,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: FlutterFlowTheme.of(context).secondaryText,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),

                // Description
                if (description.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Description',
                        style: FlutterFlowTheme.of(context).titleSmall.override(
                              font: GoogleFonts.interTight(
                                fontWeight: FontWeight.w600,
                              ),
                              color: FlutterFlowTheme.of(context).primaryText,
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        description,
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              font: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                              ),
                              color: FlutterFlowTheme.of(context).secondaryText,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 12.0),
                    ],
                  ),

                // Location
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: FlutterFlowTheme.of(context).secondaryText,
                      size: 18.0,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      location,
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            fontSize: 14.0,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Date and Time
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: FlutterFlowTheme.of(context).secondaryText,
                      size: 18.0,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      '$formattedDate at $formattedTime',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            fontSize: 14.0,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Author
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      color: FlutterFlowTheme.of(context).secondaryText,
                      size: 18.0,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      'Created by: $authorName',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            fontSize: 14.0,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Participants
                Row(
                  children: [
                    Icon(
                      Icons.group_outlined,
                      color: FlutterFlowTheme.of(context).secondaryText,
                      size: 18.0,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      '$participantCount participants',
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            font: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                            ),
                            color: FlutterFlowTheme.of(context).secondaryText,
                            fontSize: 14.0,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Tags
                if (tags.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tags',
                        style: FlutterFlowTheme.of(context).titleSmall.override(
                              font: GoogleFonts.interTight(
                                fontWeight: FontWeight.w600,
                              ),
                              color: FlutterFlowTheme.of(context).primaryText,
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4.0),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: tags.map((tag) {
                          return Container(
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context)
                                  .primaryBackground,
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(
                                color: FlutterFlowTheme.of(context).primary,
                                width: 1.0,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 4.0,
                              ),
                              child: Text(
                                tag,
                                style: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .override(
                                      font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      color:
                                          FlutterFlowTheme.of(context).primary,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                const SizedBox(height: 8.0),
                Container(
                  decoration: BoxDecoration(
                    color: isPublic
                        ? FlutterFlowTheme.of(context).primary.withOpacity(0.1)
                        : FlutterFlowTheme.of(context).error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 6.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPublic
                              ? Icons.lock_open_outlined
                              : Icons.lock_outlined,
                          color: isPublic
                              ? FlutterFlowTheme.of(context).primary
                              : FlutterFlowTheme.of(context).error,
                          size: 16.0,
                        ),
                        const SizedBox(width: 4.0),
                        Text(
                          isPublic ? 'Public Event' : 'Private Event',
                          style:
                              FlutterFlowTheme.of(context).bodySmall.override(
                                    font: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    color: isPublic
                                        ? FlutterFlowTheme.of(context).primary
                                        : FlutterFlowTheme.of(context).error,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDistance(double km) {
    if (km < 0.05) return '<50 m';
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.toStringAsFixed(0)} km';
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return Icons.music_note_rounded;
      case 'meetup':
        return Icons.people_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'art':
        return Icons.palette_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return const Color(0xFFFF6B6B); // Coral
      case 'meetup':
        return const Color(0xFF6366F1); // Indigo
      case 'food':
        return const Color(0xFFFF6B6B); // Coral
      case 'art':
        return const Color(0xFF1E293B); // Dark blue
      default:
        return const Color(0xFF4B5563); // Gray
    }
  }

  Widget _buildActiveBadge(
      BuildContext context, bool isActive, DateTime? from, DateTime? until) {
    final theme = FlutterFlowTheme.of(context);
    final now = DateTime.now();
    String label;
    Color bg;
    Color fg;
    if (isActive) {
      if (until != null) {
        final mins = until.difference(now).inMinutes;
        label = mins > 0 ? 'Live · ${mins}m left' : 'Live';
      } else {
        label = 'Live';
      }
      bg = Colors.green.withOpacity(0.15);
      fg = Colors.green.shade700;
    } else if (from != null && from.isAfter(now)) {
      final diff = from.difference(now);
      final hrs = diff.inHours;
      if (hrs >= 1) {
        label = 'Starts in ${hrs}h';
      } else {
        label = 'Starts in ${diff.inMinutes}m';
      }
      bg = theme.primary.withOpacity(0.12);
      fg = theme.primary;
    } else {
      label = 'Ended';
      bg = theme.secondaryText.withOpacity(0.15);
      fg = theme.secondaryText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.bodySmall.override(
          font: GoogleFonts.inter(fontWeight: FontWeight.w600),
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
