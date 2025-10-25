import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../backend/api_service.dart';
import '../../components/skeleton_loader.dart';
import '../../components/error_state_widget.dart';
import '../../components/refresh_indicator.dart';
import '../../components/micro_interactions.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/snackbar_utils.dart';

/// EXAMPLE: Enhanced Messages List with all UX improvements
/// This demonstrates how to apply the new UX components to an existing page

class EnhancedMessagesListExample extends ConsumerStatefulWidget {
  const EnhancedMessagesListExample({Key? key}) : super(key: key);

  @override
  ConsumerState<EnhancedMessagesListExample> createState() =>
      _EnhancedMessagesListExampleState();
}

class _EnhancedMessagesListExampleState
    extends ConsumerState<EnhancedMessagesListExample> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));
      final result = await ApiService.instance.listConversations();

      if (mounted) {
        setState(() {
          _conversations = result ?? [];
          _isLoading = false;
        });

        // ✨ UX Improvement: Success feedback
        if (_conversations.isNotEmpty) {
          await HapticUtils.light();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });

        // ✨ UX Improvement: Error haptic feedback
        await HapticUtils.error();

        // ✨ UX Improvement: Informative error snackbar
        if (mounted) {
          CustomSnackbar.showError(
            context,
            message: 'Failed to load conversations',
            actionLabel: 'Retry',
            onAction: _loadConversations,
          );
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    // ✨ UX Improvement: Light haptic on pull
    await HapticUtils.light();
    await _loadConversations();
  }

  void _openConversation(Map<String, dynamic> conversation) async {
    // ✨ UX Improvement: Selection haptic
    await HapticUtils.selection();

    // Navigate to conversation
    // Navigator.push(...)

    // ✨ UX Improvement: Success feedback after navigation
    CustomSnackbar.showInfo(
      context,
      message: 'Opening conversation...',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Messages', style: theme.titleLarge),
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(FlutterFlowTheme theme) {
    // ✨ UX Improvement: Skeleton loader instead of spinner
    if (_isLoading) {
      return SkeletonListView(
        itemCount: 8,
        itemBuilder: (context, index) => const ConversationItemSkeleton(),
      );
    }

    // ✨ UX Improvement: Enhanced error state with retry
    if (_hasError) {
      return ErrorStateWidget(
        title: 'Unable to Load Messages',
        message: 'Check your connection and try again',
        icon: Icons.chat_bubble_outline_rounded,
        onRetry: _loadConversations,
      );
    }

    // ✨ UX Improvement: Empty state with helpful message
    if (_conversations.isEmpty) {
      return EmptyStateWidget(
        title: 'No Conversations Yet',
        message: 'Start chatting with people nearby!',
        icon: Icons.chat_bubble_outline,
        actionText: 'Find People',
        onAction: () {
          // Navigate to discovery
        },
      );
    }

    // ✨ UX Improvement: Pull to refresh
    return CustomRefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];

          // ✨ UX Improvement: Slide in animation for list items
          return SlideInAnimation(
            index: index,
            child: _buildConversationCard(conversation, theme),
          );
        },
      ),
    );
  }

  Widget _buildConversationCard(
    Map<String, dynamic> conversation,
    FlutterFlowTheme theme,
  ) {
    final name = conversation['otherUserName'] as String? ?? 'Unknown';
    final lastMessage = conversation['lastMessage'] as String? ?? '';
    final avatarUrl = conversation['otherUserPhotoUrl'] as String?;
    final unreadCount = conversation['unreadCount'] as int? ?? 0;

    // ✨ UX Improvement: Animated card with haptic feedback
    return HapticCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: () => _openConversation(conversation),
      feedbackType: HapticsType.light,
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 28,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                : null,
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.titleMedium.override(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unreadCount > 0)
                      // ✨ UX Improvement: Pulse animation for unread indicator
                      PulseAnimation(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  lastMessage,
                  style: theme.bodySmall.override(
                    color: theme.secondaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// EXAMPLE: Enhanced Create Pulse Form with validation
class EnhancedCreatePulseFormExample extends StatefulWidget {
  const EnhancedCreatePulseFormExample({Key? key}) : super(key: key);

  @override
  State<EnhancedCreatePulseFormExample> createState() =>
      _EnhancedCreatePulseFormExampleState();
}

class _EnhancedCreatePulseFormExampleState
    extends State<EnhancedCreatePulseFormExample> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      // ✨ UX Improvement: Shake animation and error haptic for validation failure
      await HapticUtils.error();
      CustomSnackbar.showError(
        context,
        message: 'Please fill in all required fields',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // ✨ UX Improvement: Show loading dialog
    LoadingDialog.show(context, message: 'Creating your pulse...');

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));

      // Success
      if (mounted) {
        LoadingDialog.hide(context);

        // ✨ UX Improvement: Success haptic and snackbar
        await HapticUtils.success();
        CustomSnackbar.showSuccess(
          context,
          message: 'Pulse created successfully! 🎉',
        );

        // Navigate back
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        LoadingDialog.hide(context);
        setState(() => _isSubmitting = false);

        // ✨ UX Improvement: Error haptic and snackbar with retry
        await HapticUtils.error();
        CustomSnackbar.showError(
          context,
          message: 'Failed to create pulse',
          actionLabel: 'Retry',
          onAction: _submitForm,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Create Pulse', style: theme.titleLarge),
        backgroundColor: theme.secondaryBackground,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ✨ UX Improvement: Validated text field with real-time feedback
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title *',
                hintText: 'What\'s happening?',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Title is required';
                }
                if (value.length < 3) {
                  return 'Title must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Description *',
                hintText: 'Tell people more about your pulse...',
                prefixIcon: const Icon(Icons.description),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Description is required';
                }
                if (value.length < 10) {
                  return 'Description must be at least 10 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ✨ UX Improvement: Animated button with haptic feedback
            AnimatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              backgroundColor: theme.primary,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _isSubmitting ? 'Creating...' : 'Create Pulse',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
