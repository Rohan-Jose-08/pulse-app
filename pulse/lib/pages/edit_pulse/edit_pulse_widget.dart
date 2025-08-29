import 'dart:io';
import '/backend/api_service.dart';
import '/backend/storage_service.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditPulseWidget extends StatefulWidget {
  const EditPulseWidget({super.key, required this.pulse});
  final Map<String, dynamic> pulse; // existing pulse data
  static String routeName = 'EditPulse';
  static String routePath = '/pulse/:id/edit';

  @override
  State<EditPulseWidget> createState() => _EditPulseWidgetState();
}

class _EditPulseWidgetState extends State<EditPulseWidget> {
  late TextEditingController _titleCtl;
  late TextEditingController _descCtl;
  late TextEditingController _tagCtl;
  bool _isPublic = true;
  DateTime? _eventTime;
  final List<String> _tags = [];
  bool _saving = false;
  File? _imageFile;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleCtl =
        TextEditingController(text: widget.pulse['title']?.toString() ?? '');
    _descCtl = TextEditingController(
        text: widget.pulse['description']?.toString() ?? '');
    _tagCtl = TextEditingController();
    _isPublic = widget.pulse['isPublic'] == true;
    if (widget.pulse['eventTime'] != null) {
      try {
        _eventTime = DateTime.parse(widget.pulse['eventTime']);
      } catch (_) {}
    }
    if (widget.pulse['tags'] is List) {
      for (final t in (widget.pulse['tags'] as List)) {
        if (t is String) _tags.add(t);
      }
    }
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    _tagCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) {
      setState(() {
        _imageFile = File(x.path);
      });
    }
  }

  void _addTag() {
    final v = _tagCtl.text.trim();
    if (v.isNotEmpty && !_tags.contains(v)) {
      setState(() {
        _tags.add(v);
        _tagCtl.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _save() async {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) {
      _snack('Title required');
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      String? imageUrl = widget.pulse['imageUrl'];
      if (_imageFile != null) {
        _snack('Uploading image...');
        imageUrl = await StorageService().uploadPulseImage(_imageFile!);
      }
      final updated = await ApiService.instance.patchPulse(
        pulseId: widget.pulse['id'],
        fields: {
          'title': title,
          'description': _descCtl.text.trim(),
          'eventTime': _eventTime?.toIso8601String(),
          'isPublic': _isPublic,
          'tags': _tags,
          if (imageUrl != null) 'imageUrl': imageUrl,
        },
      );
      if (updated != null) {
        if (!mounted) return;
        _snack('Pulse updated');
        Navigator.of(context).pop(updated);
      } else {
        _snack('Update failed');
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted)
        setState(() {
          _saving = false;
        });
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Pulse'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtl,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 3,
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Text(_eventTime != null
                      ? dateTimeFormat('yMMMd jm', _eventTime)
                      : 'No time selected')),
              TextButton(
                  onPressed: () async {
                    final dt = await showDatePicker(
                        context: context,
                        initialDate: _eventTime ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (dt != null) {
                      final tm = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                              _eventTime ?? DateTime.now()));
                      if (tm != null) {
                        setState(() => _eventTime = DateTime(
                            dt.year, dt.month, dt.day, tm.hour, tm.minute));
                      }
                    }
                  },
                  child: const Text('Pick Time'))
            ],
          ),
          SwitchListTile(
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: const Text('Public')),
          Wrap(
            spacing: 8,
            children: _tags
                .map(
                    (t) => Chip(label: Text(t), onDeleted: () => _removeTag(t)))
                .toList(),
          ),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _tagCtl,
                    decoration: const InputDecoration(labelText: 'Add tag'))),
            IconButton(onPressed: _addTag, icon: const Icon(Icons.add))
          ]),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.alternate),
                image: _imageFile != null
                    ? DecorationImage(
                        image: FileImage(_imageFile!), fit: BoxFit.cover)
                    : (widget.pulse['imageUrl'] != null
                        ? DecorationImage(
                            image: NetworkImage(widget.pulse['imageUrl']),
                            fit: BoxFit.cover)
                        : null),
              ),
              child: _imageFile == null && widget.pulse['imageUrl'] == null
                  ? Center(
                      child: Text('Tap to add image', style: theme.bodyMedium))
                  : null,
            ),
          ),
          const SizedBox(height: 32),
          FFButtonWidget(
              onPressed: _saving ? null : _save,
              text: 'Save Changes',
              options: FFButtonOptions(
                  width: double.infinity,
                  height: 50,
                  color: theme.primary,
                  textStyle: theme.titleSmall.copyWith(color: Colors.white),
                  borderRadius: BorderRadius.circular(25)))
        ],
      ),
    );
  }
}
