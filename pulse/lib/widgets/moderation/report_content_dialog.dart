import 'package:flutter/material.dart';
import '../../services/moderation_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';

/// Report content dialog widget
class ReportContentDialog extends StatefulWidget {
  final String? reportedUserId;
  final String? reportedPulseId;
  final String? reportedMessageId;
  final String? reportedHighlightId;
  final String? reportedPostId;
  final String contentType; // 'user', 'pulse', 'message', 'highlight', 'post'

  const ReportContentDialog({
    super.key,
    this.reportedUserId,
    this.reportedPulseId,
    this.reportedMessageId,
    this.reportedHighlightId,
    this.reportedPostId,
    required this.contentType,
  });

  @override
  State<ReportContentDialog> createState() => _ReportContentDialogState();

  /// Show the report dialog
  static Future<bool?> show(
    BuildContext context, {
    String? reportedUserId,
    String? reportedPulseId,
    String? reportedMessageId,
    String? reportedHighlightId,
    String? reportedPostId,
    required String contentType,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReportContentDialog(
        reportedUserId: reportedUserId,
        reportedPulseId: reportedPulseId,
        reportedMessageId: reportedMessageId,
        reportedHighlightId: reportedHighlightId,
        reportedPostId: reportedPostId,
        contentType: contentType,
      ),
    );
  }
}

class _ReportContentDialogState extends State<ReportContentDialog> {
  final ModerationService _moderationService = ModerationService.instance;
  final TextEditingController _descriptionController = TextEditingController();

  ReportCategory? _selectedCategory;
  String? _selectedSubcategory;
  bool _isSubmitting = false;
  int _currentStep = 0;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  String get _contentTypeLabel {
    switch (widget.contentType) {
      case 'user':
        return 'user';
      case 'pulse':
        return 'Pulse';
      case 'message':
        return 'message';
      case 'highlight':
        return 'highlight';
      case 'post':
        return 'post';
      default:
        return 'content';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.alternate,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _currentStep > 0
                            ? Icons.arrow_back_rounded
                            : Icons.close_rounded,
                        color: theme.primaryText,
                      ),
                      onPressed: () {
                        if (_currentStep > 0) {
                          setState(() => _currentStep--);
                        } else {
                          Navigator.pop(context, false);
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        _getStepTitle(),
                        style: theme.headlineSmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48), // Balance for back button
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: _buildStepContent(scrollController),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Report $_contentTypeLabel';
      case 1:
        return _selectedCategory?.label ?? 'Select reason';
      case 2:
        return 'Additional details';
      default:
        return 'Report';
    }
  }

  Widget _buildStepContent(ScrollController scrollController) {
    switch (_currentStep) {
      case 0:
        return _buildCategorySelection(scrollController);
      case 1:
        return _buildSubcategorySelection(scrollController);
      case 2:
        return _buildDetailsStep(scrollController);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCategorySelection(ScrollController scrollController) {
    final theme = FlutterFlowTheme.of(context);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Why are you reporting this $_contentTypeLabel?',
          style: theme.bodyLarge.copyWith(
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(height: 16),
        ...ReportCategory.values.map((category) {
          return _buildCategoryTile(category);
        }),
      ],
    );
  }

  Widget _buildCategoryTile(ReportCategory category) {
    final theme = FlutterFlowTheme.of(context);
    final isSelected = _selectedCategory == category;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.primary.withOpacity(0.1)
            : theme.primaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? theme.primary : theme.alternate,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: () {
          setState(() {
            _selectedCategory = category;
            _selectedSubcategory = null;
            _currentStep = 1;
          });
        },
        leading: Icon(
          _getCategoryIcon(category),
          color: isSelected ? theme.primary : theme.secondaryText,
        ),
        title: Text(
          category.label,
          style: theme.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: isSelected ? theme.primary : theme.primaryText,
          ),
        ),
        subtitle: Text(
          category.description,
          style: theme.bodySmall.copyWith(
            color: theme.secondaryText,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: theme.secondaryText,
        ),
      ),
    );
  }

  IconData _getCategoryIcon(ReportCategory category) {
    switch (category) {
      case ReportCategory.spam:
        return Icons.report_gmailerrorred_rounded;
      case ReportCategory.harassment:
        return Icons.person_off_rounded;
      case ReportCategory.hateSpeed:
        return Icons.mood_bad_rounded;
      case ReportCategory.violence:
        return Icons.warning_amber_rounded;
      case ReportCategory.inappropriate:
        return Icons.visibility_off_rounded;
      case ReportCategory.scam:
        return Icons.gpp_bad_rounded;
      case ReportCategory.impersonation:
        return Icons.person_outline_rounded;
      case ReportCategory.other:
        return Icons.more_horiz_rounded;
    }
  }

  Widget _buildSubcategorySelection(ScrollController scrollController) {
    final theme = FlutterFlowTheme.of(context);
    final subcategories =
        ReportSubcategories.subcategories[_selectedCategory] ?? [];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'What specifically is the issue?',
          style: theme.bodyLarge.copyWith(
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(height: 16),
        ...subcategories.map((subcategory) {
          final isSelected = _selectedSubcategory == subcategory;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.primary.withOpacity(0.1)
                  : theme.primaryBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? theme.primary : theme.alternate,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ListTile(
              onTap: () {
                setState(() {
                  _selectedSubcategory = subcategory;
                  _currentStep = 2;
                });
              },
              title: Text(
                subcategory,
                style: theme.bodyLarge.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isSelected ? theme.primary : theme.primaryText,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.secondaryText,
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () {
            setState(() {
              _selectedSubcategory = null;
              _currentStep = 2;
            });
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(color: theme.alternate),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Skip this step',
            style: theme.bodyMedium.copyWith(
              color: theme.secondaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsStep(ScrollController scrollController) {
    final theme = FlutterFlowTheme.of(context);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.primaryBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getCategoryIcon(_selectedCategory!),
                    color: theme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedCategory!.label,
                    style: theme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (_selectedSubcategory != null) ...[
                const SizedBox(height: 8),
                Text(
                  _selectedSubcategory!,
                  style: theme.bodyMedium.copyWith(
                    color: theme.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Description field
        Text(
          'Additional details (optional)',
          style: theme.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            hintText:
                'Provide any additional context that might help us review this report...',
            hintStyle: theme.bodyMedium.copyWith(
              color: theme.secondaryText,
            ),
            filled: true,
            fillColor: theme.primaryBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.alternate),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.alternate),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primary, width: 2),
            ),
          ),
          style: theme.bodyMedium,
        ),
        const SizedBox(height: 24),
        // Info text
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: theme.info,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Our team will review your report and take appropriate action. We may contact you for additional information.',
                  style: theme.bodySmall.copyWith(
                    color: theme.info,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Submit button
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSubmitting
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  'Submit Report',
                  style: theme.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _submitReport() async {
    if (_selectedCategory == null) return;

    setState(() => _isSubmitting = true);

    try {
      final success = await _moderationService.reportContent(
        reportedUserId: widget.reportedUserId,
        reportedPulseId: widget.reportedPulseId,
        reportedMessageId: widget.reportedMessageId,
        reportedHighlightId: widget.reportedHighlightId,
        reportedPostId: widget.reportedPostId,
        category: _selectedCategory!,
        subcategory: _selectedSubcategory,
        description: _descriptionController.text.isNotEmpty
            ? _descriptionController.text
            : null,
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Report submitted. Thank you for helping keep our community safe.'),
              backgroundColor: FlutterFlowTheme.of(context).success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to submit report. Please try again.'),
              backgroundColor: FlutterFlowTheme.of(context).error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
