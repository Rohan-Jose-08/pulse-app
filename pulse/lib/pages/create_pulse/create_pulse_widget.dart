import 'dart:io';
import 'dart:ui';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:flutter_animate/flutter_animate.dart';

import '/backend/api_service.dart';
import '/flutter_flow/flutter_flow_google_map.dart';
import '/flutter_flow/flutter_flow_icon_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'create_pulse_model.dart';

/// Create a "Create Pulse" page for a social app named **Pulse**, using
/// Flutter and Firebase Auth.
///
/// This form allows logged-in users to submit event ("Pulse") data based on
/// the following Prisma schema:
///
// ============================================================================
// Create Pulse (clean enhanced implementation)
// ============================================================================
class CreatePulseWidget extends StatefulWidget {
  const CreatePulseWidget({super.key});
  static String routeName = 'CreatePulse';
  static String routePath = '/createPulse';
  @override
  State<CreatePulseWidget> createState() => _CreatePulseWidgetState();
}

class _CreatePulseWidgetState extends State<CreatePulseWidget> {
  late CreatePulseModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();

  File? _imageFile;
  bool _submitting = false;
  bool _expandedDescription = true;
  bool _expandedTags = true;
  bool _expandedMedia = true;
  bool _expandedVisibility = true;
  bool _expandedActiveWindow = true;
  bool _expandedLocation = false;
  bool _geocodingAddress = false;
  String? _resolvedAddress; // store the formatted / typed address

  final List<String> _tags = [];
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _tagFocus = FocusNode();

  static const List<String> _tagSuggestions = [
    'music',
    'sports',
    'tech',
    'networking',
    'food',
    'fitness',
    'art',
    'gaming',
    'study',
    'travel'
  ];

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => CreatePulseModel());
    _model.textController1 ??= TextEditingController();
    _model.textFieldFocusNode1 ??= FocusNode();
    _model.textController2 ??= TextEditingController();
    _model.textFieldFocusNode2 ??= FocusNode();
    _model.textController3 ??= TextEditingController();
    _model.textFieldFocusNode3 ??= FocusNode();
    _model.switchValue = true;
    _activeDurationMinutes = 120; // default 2h
    _startOffsetMinutes = 0; // start at event time by default
  }

  @override
  void dispose() {
    _tagController.dispose();
    _tagFocus.dispose();
    _model.dispose();
    super.dispose();
  }

  void _addTag() {
    final t = _tagController.text.trim();
    if (t.isEmpty) return;
    if (!_tags.contains(t)) setState(() => _tags.add(t));
    _tagController.clear();
  }

  void _removeTag(String t) => setState(() => _tags.remove(t));

  int _activeDurationMinutes = 120; // adjustable (15 min to 24h)
  int _startOffsetMinutes = 0; // negative = before eventTime, positive = after
  bool _useCustomWindow =
      false; // when false we just send duration, backend derives

  String _formatMinutes(int mins) {
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  DateTime? _computeActiveFrom(DateTime eventTime) {
    if (!_useCustomWindow) return null; // let backend default to eventTime
    return eventTime.add(Duration(minutes: _startOffsetMinutes));
  }

  DateTime? _computeActiveUntil(DateTime eventTime) {
    if (_useCustomWindow) {
      final from = eventTime.add(Duration(minutes: _startOffsetMinutes));
      return from.add(Duration(minutes: _activeDurationMinutes));
    }
    return null; // backend will derive using duration
  }

  Future<void> _createPulse() async {
    final title = _model.textController1?.text.trim() ?? '';
    final description = _model.textController2?.text.trim() ?? '';
    final time = _model.datePicked;
    if (title.isEmpty || time == null) {
      _snack('Title & time required');
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);

    String? location; // optional human-readable label typed/resolved
    double? latitude;
    double? longitude;
    if (_model.googleMapsCenter != null) {
      latitude = _model.googleMapsCenter!.latitude;
      longitude = _model.googleMapsCenter!.longitude;
    }
    if (_resolvedAddress != null && _resolvedAddress!.isNotEmpty) {
      location = _resolvedAddress;
    }

    String? imageUrl;
    if (_imageFile != null) {
      try {
        final ref = FirebaseStorage.instance.ref().child(
            'pulses/${DateTime.now().millisecondsSinceEpoch}_${_imageFile!.path.split('/').last}');
        final snap = await ref.putFile(_imageFile!).whenComplete(() {});
        imageUrl = await snap.ref.getDownloadURL();
      } catch (_) {
        _snack('Image upload failed');
      }
    }

    final created = await ApiService.instance.createPulse(
      title: title,
      description: description.isNotEmpty ? description : null,
      location: location,
      eventTime: time,
      isPublic: _model.switchValue ?? true,
      tags: _tags,
      imageUrl: imageUrl,
      latitude: latitude,
      longitude: longitude,
      activeDurationMinutes: _activeDurationMinutes,
      activeFrom: _computeActiveFrom(time),
      activeUntil: _computeActiveUntil(time),
    );

    if (!mounted) return;
    if (created != null) {
      _snack('Pulse created');
      context.safePop();
    } else {
      _snack('Failed to create');
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _resolveTypedAddress() async {
    final query = _model.textController3?.text.trim();
    if (query == null || query.isEmpty) {
      _snack('Enter an address');
      return;
    }
    setState(() => _geocodingAddress = true);
    try {
      final results = await geocoding.locationFromAddress(query);
      if (results.isNotEmpty) {
        final first = results.first;
        setState(() {
          _model.googleMapsCenter = LatLng(first.latitude, first.longitude);
          _resolvedAddress = query; // keep original typed address
        });
      } else {
        _snack('No results');
      }
    } catch (e) {
      _snack('Address lookup failed');
    } finally {
      if (mounted) setState(() => _geocodingAddress = false);
    }
  }

  InputDecoration _dec(String hint) {
    final t = FlutterFlowTheme.of(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: t.bodyMedium
          .override(font: GoogleFonts.inter(), color: t.secondaryText),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.alternate)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.primary)),
      filled: true,
      fillColor: t.secondaryBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Future<void> _imageSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(runSpacing: 12, children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).alternate,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 8),
            Text('Add Image', style: FlutterFlowTheme.of(context).titleMedium),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () async {
                final p = await ImagePicker()
                    .pickImage(source: ImageSource.gallery, imageQuality: 72);
                if (p != null) setState(() => _imageFile = File(p.path));
                if (mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () async {
                final p = await ImagePicker()
                    .pickImage(source: ImageSource.camera, imageQuality: 72);
                if (p != null) setState(() => _imageFile = File(p.path));
                if (mounted) Navigator.pop(ctx);
              },
            ),
            if (_imageFile != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Remove'),
                onTap: () {
                  setState(() => _imageFile = null);
                  Navigator.pop(ctx);
                },
              )
          ]),
        ),
      ),
    );
  }

  Future<void> _mapSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                      color: FlutterFlowTheme.of(context).alternate,
                      borderRadius: BorderRadius.circular(2)))),
          Text('Select Location',
              style: FlutterFlowTheme.of(context).titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: FlutterFlowGoogleMap(
              controller: _model.googleMapsController,
              onCameraIdle: (l) => _model.googleMapsCenter = l,
              initialLocation: _model.googleMapsCenter ??=
                  const LatLng(13.106061, -59.613158),
              markerColor: GoogleMarkerColor.violet,
              mapType: MapType.normal,
              style: GoogleMapStyle.standard,
              initialZoom: 14,
              allowInteraction: true,
              allowZoom: true,
              showZoomControls: true,
              showLocation: true,
              showCompass: false,
              showMapToolbar: false,
              showTraffic: false,
              centerMapOnMarkerTap: true,
              mapTakesGesturePreference: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: FFButtonWidget(
              onPressed: () => Navigator.pop(ctx),
              text: 'Use This Location',
              options: FFButtonOptions(
                height: 48,
                color: FlutterFlowTheme.of(context).primary,
                textStyle: FlutterFlowTheme.of(context).titleSmall.override(
                    font: GoogleFonts.interTight(fontWeight: FontWeight.w600),
                    color: Colors.white),
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )
        ]),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: theme.primaryBackground,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 10),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF1A1A2E).withOpacity(0.9),
                          const Color(0xFF16213E).withOpacity(0.85),
                        ]
                      : [
                          Colors.white.withOpacity(0.9),
                          Colors.white.withOpacity(0.85),
                        ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.05),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.safePop(),
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: theme.primaryText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
                          ).createShader(bounds),
                          child: Text(
                            'Create Pulse',
                            style: theme.headlineSmall.override(
                              font: GoogleFonts.interTight(
                                  fontWeight: FontWeight.w700),
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: _submitting
                              ? LinearGradient(
                                  colors: [
                                    const Color(0xFFEC4899).withOpacity(0.5),
                                    const Color(0xFFF43F5E).withOpacity(0.5),
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFEC4899),
                                    Color(0xFFF43F5E)
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: _submitting
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(0xFFEC4899)
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _submitting
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    _createPulse();
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              child: Text(
                                _submitting ? 'Saving...' : 'Create',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              kToolbarHeight + 30,
              20,
              40 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title & Time (responsive)
                LayoutBuilder(builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 560;
                  final titleField = _SectionCard(
                    label: 'Title',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _model.textController1,
                          focusNode: _model.textFieldFocusNode1,
                          maxLength: 80,
                          buildCounter: (context,
                                  {required int currentLength,
                                  required bool isFocused,
                                  int? maxLength}) =>
                              null,
                          onChanged: (_) => setState(() {}),
                          decoration: _dec("What's happening?"),
                          style: theme.bodyMedium.override(
                              font: GoogleFonts.inter(), fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _CharCount(
                            current: _model.textController1!.text.length,
                            max: 80,
                          ),
                        ),
                      ],
                    ),
                  );
                  final timeField = _SectionCard(
                    label: 'Event Time',
                    child: _DateTimeField(
                      dateTime: _model.datePicked,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _model.datePicked ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2050),
                        );
                        if (d != null) {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                                _model.datePicked ?? DateTime.now()),
                          );
                          if (t != null) {
                            setState(() => _model.datePicked = DateTime(
                                  d.year,
                                  d.month,
                                  d.day,
                                  t.hour,
                                  t.minute,
                                ));
                          }
                        }
                      },
                    ),
                  );
                  if (narrow) {
                    return Column(
                      children: [
                        titleField,
                        const SizedBox(height: 16),
                        timeField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: titleField),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: timeField),
                    ],
                  );
                }),
                const SizedBox(height: 24),
                // Active Window
                _ExpandableCard(
                  label: 'Active Window',
                  expanded: _expandedActiveWindow,
                  onToggle: () => setState(
                      () => _expandedActiveWindow = !_expandedActiveWindow),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Duration', style: theme.titleSmall),
                              Slider(
                                min: 15,
                                max: 1440,
                                divisions: (1440 - 15),
                                value: _activeDurationMinutes
                                    .toDouble()
                                    .clamp(15, 1440),
                                label: _formatMinutes(_activeDurationMinutes),
                                onChanged: (v) => setState(
                                    () => _activeDurationMinutes = v.round()),
                              ),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final preset in [
                                  30,
                                  60,
                                  90,
                                  120,
                                  180,
                                  240,
                                  480,
                                  720,
                                  1440
                                ])
                                  ChoiceChip(
                                    label: Text(_formatMinutes(preset)),
                                    selected: _activeDurationMinutes == preset,
                                    onSelected: (_) => setState(
                                        () => _activeDurationMinutes = preset),
                                  ),
                              ])
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Custom start offset'),
                        subtitle: Text(_useCustomWindow
                            ? _startOffsetMinutes == 0
                                ? 'Starts exactly at event time'
                                : (_startOffsetMinutes > 0
                                    ? 'Starts ${_formatMinutes(_startOffsetMinutes)} after event'
                                    : 'Starts ${_formatMinutes(_startOffsetMinutes.abs())} before event')
                            : 'Starts at event time (default)'),
                        value: _useCustomWindow,
                        onChanged: (v) => setState(() => _useCustomWindow = v),
                      ),
                      if (_useCustomWindow) ...[
                        Row(children: [
                          Expanded(
                            child: Slider(
                              min: -720, // 12h before
                              max: 720, // 12h after
                              divisions: 1440,
                              value: _startOffsetMinutes.toDouble(),
                              label: _startOffsetMinutes == 0
                                  ? 'At event time'
                                  : (_startOffsetMinutes > 0
                                      ? '+${_formatMinutes(_startOffsetMinutes)}'
                                      : '-${_formatMinutes(_startOffsetMinutes.abs())}'),
                              onChanged: (v) => setState(
                                  () => _startOffsetMinutes = v.round()),
                            ),
                          ),
                        ]),
                        Text(
                          'Active From Preview: ' +
                              (_model.datePicked != null
                                  ? dateTimeFormat(
                                      'MMM d, h:mm a',
                                      _computeActiveFrom(_model.datePicked!) ??
                                          _model.datePicked!)
                                  : 'Select event time'),
                          style: theme.bodySmall,
                        ),
                        Text(
                          'Active Until Preview: ' +
                              (_model.datePicked != null
                                  ? dateTimeFormat(
                                      'MMM d, h:mm a',
                                      _computeActiveUntil(_model.datePicked!) ??
                                          _model.datePicked!)
                                  : 'Select event time'),
                          style: theme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'The active window controls when the pulse is considered live. Default is event time plus chosen duration.',
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(fontSize: 12),
                          color: theme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Description
                _ExpandableCard(
                  label: 'Description',
                  expanded: _expandedDescription,
                  onToggle: () => setState(
                      () => _expandedDescription = !_expandedDescription),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _model.textController2,
                        focusNode: _model.textFieldFocusNode2,
                        maxLines: 5,
                        minLines: 3,
                        maxLength: 500,
                        buildCounter: (context,
                                {required int currentLength,
                                required bool isFocused,
                                int? maxLength}) =>
                            null,
                        onChanged: (_) => setState(() {}),
                        decoration: _dec('Tell us more...'),
                        style: theme.bodyMedium
                            .override(font: GoogleFonts.inter(), fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _CharCount(
                          current: _model.textController2!.text.length,
                          max: 500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Tags
                _ExpandableCard(
                  label: 'Tags',
                  expanded: _expandedTags,
                  onToggle: () =>
                      setState(() => _expandedTags = !_expandedTags),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.secondaryBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.alternate),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: -8,
                          children: [
                            for (final tag in _tags)
                              Chip(
                                label: Text(
                                  tag,
                                  style: theme.bodySmall.override(
                                    font: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500),
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: theme.primary,
                                deleteIcon: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                                onDeleted: () => _removeTag(tag),
                              ),
                            SizedBox(
                              width: 140,
                              child: RawKeyboardListener(
                                focusNode: _tagFocus,
                                onKey: (evt) {
                                  if (evt is RawKeyDownEvent) {
                                    if (evt.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        evt.logicalKey ==
                                            LogicalKeyboardKey.space) {
                                      _addTag();
                                    }
                                  }
                                },
                                child: TextField(
                                  controller: _tagController,
                                  onSubmitted: (_) => _addTag(),
                                  maxLength: 20,
                                  decoration: const InputDecoration(
                                    hintText: 'Add tag',
                                    border: InputBorder.none,
                                    counterText: '',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _tagSuggestions.map((s) {
                          final sel = _tags.contains(s);
                          return FilterChip(
                            label: Text(s),
                            selected: sel,
                            onSelected: (_) => sel
                                ? _removeTag(s)
                                : setState(() => _tags.add(s)),
                            selectedColor: theme.primary,
                            checkmarkColor: Colors.white,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Media
                _ExpandableCard(
                  label: 'Media',
                  expanded: _expandedMedia,
                  onToggle: () =>
                      setState(() => _expandedMedia = !_expandedMedia),
                  child: GestureDetector(
                    onTap: _imageSheet,
                    onLongPress: () {
                      if (_imageFile != null) setState(() => _imageFile = null);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.alternate),
                        color: theme.secondaryBackground,
                        image: _imageFile != null
                            ? DecorationImage(
                                image: FileImage(_imageFile!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _imageFile == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_outlined,
                                      size: 48, color: theme.secondaryText),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to add image',
                                    style: theme.bodyMedium.override(
                                      font: GoogleFonts.inter(),
                                      color: theme.secondaryText,
                                    ),
                                  ),
                                  Text(
                                    'Long press to clear',
                                    style: theme.bodySmall.override(
                                      font: GoogleFonts.inter(),
                                      color:
                                          theme.secondaryText.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit,
                                        color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Change',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Location
                _ExpandableCard(
                  label: 'Location',
                  expanded: _expandedLocation,
                  onToggle: () =>
                      setState(() => _expandedLocation = !_expandedLocation),
                  action: TextButton.icon(
                    onPressed: _mapSheet,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Pick on Map'),
                  ),
                  child: Builder(
                    builder: (_) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Address input row
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _model.textController3,
                                  decoration: _dec('Type an address or place'),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _resolveTypedAddress(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _geocodingAddress
                                      ? null
                                      : _resolveTypedAddress,
                                  icon: _geocodingAddress
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.search, size: 18),
                                  label: Text(
                                      _geocodingAddress ? 'Searching' : 'Use'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_model.googleMapsCenter != null)
                            Wrap(
                              children: [
                                _LocationChip(
                                  lat: _model.googleMapsCenter!.latitude,
                                  lng: _model.googleMapsCenter!.longitude,
                                  onClear: () => setState(() {
                                    _model.googleMapsCenter = null;
                                    _resolvedAddress = null;
                                  }),
                                ),
                                if (_resolvedAddress != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Chip(
                                      label: Text(
                                        _resolvedAddress!,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                              ],
                            )
                          else
                            Text(
                              'No location selected',
                              style: theme.bodyMedium.override(
                                font: GoogleFonts.inter(),
                                color: theme.secondaryText,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'You can either type an address and tap Use, or pick on map. Only one location will be saved.',
                            style: theme.bodySmall.override(
                              font: GoogleFonts.inter(fontSize: 12),
                              color: theme.secondaryText.withOpacity(0.8),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Visibility
                _ExpandableCard(
                  label: 'Visibility',
                  expanded: _expandedVisibility,
                  onToggle: () => setState(
                      () => _expandedVisibility = !_expandedVisibility),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Public Event',
                              style: theme.titleMedium.override(
                                font: GoogleFonts.interTight(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              'Anyone can discover and join this pulse',
                              style: theme.bodySmall.override(
                                font: GoogleFonts.inter(),
                                color: theme.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _model.switchValue ?? true,
                        onChanged: (v) =>
                            setState(() => _model.switchValue = v),
                        activeColor: theme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Submit Button
                Container(
                  decoration: BoxDecoration(
                    gradient: _submitting
                        ? LinearGradient(
                            colors: [
                              const Color(0xFFEC4899).withOpacity(0.5),
                              const Color(0xFFF43F5E).withOpacity(0.5),
                            ],
                          )
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
                          ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _submitting
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFFEC4899).withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _submitting
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              _createPulse();
                            },
                      child: Container(
                        height: 60,
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_submitting)
                              const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            const SizedBox(width: 12),
                            Text(
                              _submitting ? 'Creating...' : 'Create Pulse',
                              style: GoogleFonts.interTight(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2, end: 0),
                const SizedBox(height: 20),
              ],
            ),
          ), // end SingleChildScrollView
          if (_submitting)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _submitting ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFEC4899).withOpacity(0.2),
                                      const Color(0xFFF43F5E).withOpacity(0.2),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox(
                                  height: 32,
                                  width: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation(
                                        Color(0xFFEC4899)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Creating Pulse...',
                                style: GoogleFonts.interTight(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]), // end Stack
      ), // end SafeArea
    ); // end Scaffold
  }
}

// Helper components -----------------------------------------------------------
class _SectionCard extends StatelessWidget {
  final String label;
  final Widget child;
  final IconData? icon;
  const _SectionCard({required this.label, required this.child, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.15),
                    const Color(0xFF8B5CF6).withOpacity(0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(label,
              style: t.titleMedium.override(
                  font: GoogleFonts.interTight(fontWeight: FontWeight.w600))),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color:
              isDark ? const Color(0xFF1A1A2E).withOpacity(0.5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ]);
  }
}

class _ExpandableCard extends StatelessWidget {
  final String label;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final Widget? action;
  final IconData? icon;
  const _ExpandableCard(
      {required this.label,
      required this.expanded,
      required this.onToggle,
      required this.child,
      this.action,
      this.icon});
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1A1A2E).withOpacity(0.8),
                  const Color(0xFF16213E).withOpacity(0.6),
                ]
              : [
                  Colors.white,
                  Colors.grey.shade50,
                ],
        ),
        border: Border.all(
          color: expanded
              ? const Color(0xFF6366F1).withOpacity(0.3)
              : (isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05)),
          width: expanded ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: expanded
                ? const Color(0xFF6366F1).withOpacity(0.1)
                : Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: expanded ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onToggle();
              },
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6366F1).withOpacity(0.15),
                        const Color(0xFF8B5CF6).withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AnimatedRotation(
                      turns: expanded ? 0 : -0.25,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF6366F1), size: 20)),
                ),
                const SizedBox(width: 12),
                if (icon != null) ...[
                  Icon(icon, color: t.secondaryText, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: t.titleMedium.override(
                        font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
          if (action != null) action!,
        ]),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild:
              Padding(padding: const EdgeInsets.only(top: 16), child: child),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        )
      ]),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  final DateTime? dateTime;
  final VoidCallback onTap;
  const _DateTimeField({required this.dateTime, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasValue = dateTime != null;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasValue
                ? [
                    const Color(0xFF6366F1).withOpacity(isDark ? 0.15 : 0.08),
                    const Color(0xFF8B5CF6).withOpacity(isDark ? 0.1 : 0.05),
                  ]
                : isDark
                    ? [
                        const Color(0xFF1A1A2E),
                        const Color(0xFF16213E),
                      ]
                    : [
                        Colors.grey.shade50,
                        Colors.grey.shade100,
                      ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasValue
                ? const Color(0xFF6366F1).withOpacity(0.3)
                : (isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.08)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.15),
                  const Color(0xFF8B5CF6).withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Color(0xFF6366F1),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dateTime != null
                  ? dateTimeFormat('MMM d, y - h:mm a', dateTime)
                  : 'Select date & time',
              style: t.bodyMedium.override(
                font: GoogleFonts.inter(),
                color: dateTime != null ? t.primaryText : t.secondaryText,
                fontWeight:
                    dateTime != null ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: t.secondaryText.withOpacity(0.5),
            size: 20,
          ),
        ]),
      ),
    );
  }
}

class _CharCount extends StatelessWidget {
  final int current;
  final int max;
  const _CharCount({required this.current, required this.max});
  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ratio = current / max;
    final isNearLimit = ratio > 0.8;
    final isAtLimit = ratio >= 1.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAtLimit
              ? [
                  const Color(0xFFEF4444).withOpacity(0.15),
                  const Color(0xFFDC2626).withOpacity(0.15)
                ]
              : isNearLimit
                  ? [
                      const Color(0xFFF59E0B).withOpacity(0.15),
                      const Color(0xFFD97706).withOpacity(0.15)
                    ]
                  : [
                      (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                      (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAtLimit
              ? const Color(0xFFEF4444).withOpacity(0.3)
              : isNearLimit
                  ? const Color(0xFFF59E0B).withOpacity(0.3)
                  : Colors.transparent,
        ),
      ),
      child: Text(
        '$current/$max',
        style: t.bodySmall.override(
          font: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
          color: isAtLimit
              ? const Color(0xFFEF4444)
              : isNearLimit
                  ? const Color(0xFFF59E0B)
                  : t.secondaryText,
        ),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  final double lat;
  final double lng;
  final VoidCallback onClear;
  const _LocationChip(
      {required this.lat, required this.lng, required this.onClear});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withOpacity(0.15),
            const Color(0xFF059669).withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF10B981).withOpacity(0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF10B981),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
