import 'package:flutter/material.dart';
import '../components/enhanced_ui_exports.dart';

/// Example Page Demonstrating Enhanced UI Components
/// This shows practical implementations you can copy into your app
class ExampleImplementationPage extends StatefulWidget {
  const ExampleImplementationPage({Key? key}) : super(key: key);

  @override
  State<ExampleImplementationPage> createState() =>
      _ExampleImplementationPageState();
}

class _ExampleImplementationPageState extends State<ExampleImplementationPage> {
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSaving = false;
  final List<String> _messages = [];

  @override
  void dispose() {
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(Duration(seconds: 1));
    ModernSnackbar.show(
      context: context,
      message: 'Refreshed!',
      type: SnackbarType.success,
    );
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    await Future.delayed(Duration(seconds: 2));
    setState(() => _isSaving = false);

    ModernSnackbar.show(
      context: context,
      message: 'Saved successfully!',
      type: SnackbarType.success,
    );
  }

  Future<void> _handleDelete() async {
    final confirmed = await ConfirmationDialog.show(
      context: context,
      title: 'Delete Item?',
      message: 'This action cannot be undone. Are you sure?',
      confirmText: 'Delete',
      isDangerous: true,
    );

    if (confirmed == true) {
      ModernSnackbar.show(
        context: context,
        message: 'Item deleted',
        type: SnackbarType.info,
      );
    }
  }

  void _showBottomSheet() {
    ModernBottomSheet.show(
      context: context,
      title: 'Options',
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.edit),
            title: Text('Edit'),
            onTap: () {
              Navigator.pop(context);
              ModernSnackbar.show(
                context: context,
                message: 'Edit tapped',
                type: SnackbarType.info,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.share),
            title: Text('Share'),
            onTap: () {
              Navigator.pop(context);
              ModernSnackbar.show(
                context: context,
                message: 'Share tapped',
                type: SnackbarType.info,
              );
            },
          ),
          ListTile(
            leading:
                Icon(Icons.delete, color: FlutterFlowTheme.of(context).error),
            title: Text('Delete',
                style: TextStyle(color: FlutterFlowTheme.of(context).error)),
            onTap: () {
              Navigator.pop(context);
              _handleDelete();
            },
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    if (_messageController.text.isNotEmpty) {
      setState(() {
        _messages.add(_messageController.text);
        _messageController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.primaryText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Implementation Example',
          style: theme.headlineSmall,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: theme.primaryText),
            onPressed: _showBottomSheet,
          ),
        ],
      ),
      body: ModernRefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.m),
          children: [
            // Section 1: Cards
            SlideInFromBottom(
              child: _buildSection(
                title: 'Modern Cards',
                child: Column(
                  children: [
                    EnhancedPulseCard(
                      title: 'Morning Coffee Meetup',
                      subtitle: 'Join us for coffee and conversation',
                      location: 'Downtown Cafe',
                      participantCount: 12,
                      isActive: true,
                      isNearby: true,
                      imageUrl: 'https://picsum.photos/400/200',
                      onTap: () {
                        ModernSnackbar.show(
                          context: context,
                          message: 'Card tapped!',
                          type: SnackbarType.info,
                        );
                      },
                      onJoin: () {
                        ModernSnackbar.show(
                          context: context,
                          message: 'Joined pulse!',
                          type: SnackbarType.success,
                        );
                      },
                    ),
                    SizedBox(height: AppSpacing.m),
                    ModernCard(
                      useGlassmorphism: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              PulseAvatar(
                                size: 48,
                                showOnlineStatus: true,
                                isOnline: true,
                              ),
                              SizedBox(width: AppSpacing.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('John Doe', style: theme.titleMedium),
                                    Text('Active 5 min ago',
                                        style: theme.labelSmall),
                                  ],
                                ),
                              ),
                              StatusBadge(
                                text: 'Pro',
                                color: theme.tertiary,
                                icon: Icons.star,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Section 2: Forms
            SlideInFromBottom(
              delay: Duration(milliseconds: 100),
              child: _buildSection(
                title: 'Form Fields',
                child: Column(
                  children: [
                    ModernTextField(
                      controller: _emailController,
                      label: 'Email Address',
                      hint: 'Enter your email',
                      prefixIcon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: AppSpacing.m),
                    ModernTextField(
                      label: 'Password',
                      hint: 'Enter your password',
                      prefixIcon: Icons.lock,
                      suffixIcon: Icons.visibility,
                      obscureText: true,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Section 3: Buttons
            SlideInFromBottom(
              delay: Duration(milliseconds: 200),
              child: _buildSection(
                title: 'Action Buttons',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GradientButton(
                            text: 'Cancel',
                            isOutlined: true,
                            onPressed: () {
                              ModernSnackbar.show(
                                context: context,
                                message: 'Cancelled',
                                type: SnackbarType.info,
                              );
                            },
                          ),
                        ),
                        SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: GradientButton(
                            text: 'Save',
                            icon: Icons.check,
                            isLoading: _isSaving,
                            onPressed: _handleSave,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.m),
                    GradientButton(
                      text: 'Delete',
                      gradientColors: [
                        theme.error,
                        theme.error.withOpacity(0.8)
                      ],
                      icon: Icons.delete,
                      onPressed: _handleDelete,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Section 4: Messages
            SlideInFromBottom(
              delay: Duration(milliseconds: 300),
              child: _buildSection(
                title: 'Message Bubbles',
                child: Column(
                  children: [
                    ..._messages.asMap().entries.map((entry) {
                      final index = entry.key;
                      final message = entry.value;
                      return MessageBubble(
                        message: message,
                        isSent: index % 2 == 0,
                        timestamp: 'Just now',
                        isRead: true,
                        showAvatar: true,
                      );
                    }),
                    if (_messages.isEmpty)
                      EmptyStateWidget(
                        title: 'No Messages',
                        message: 'Send your first message below',
                        icon: Icons.chat_bubble_outline,
                      ),
                    SizedBox(height: AppSpacing.m),
                    Row(
                      children: [
                        Expanded(
                          child: ModernTextField(
                            controller: _messageController,
                            hint: 'Type a message...',
                            prefixIcon: Icons.message,
                          ),
                        ),
                        SizedBox(width: AppSpacing.s),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [theme.primary, theme.secondary],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Section 5: Loading States
            SlideInFromBottom(
              delay: Duration(milliseconds: 400),
              child: _buildSection(
                title: 'Loading States',
                child: Column(
                  children: [
                    GradientButton(
                      text: 'Show Loading',
                      icon: Icons.hourglass_empty,
                      onPressed: () {
                        LoadingOverlay.show(context, message: 'Processing...');
                        Future.delayed(Duration(seconds: 2), () {
                          LoadingOverlay.hide(context);
                        });
                      },
                    ),
                    SizedBox(height: AppSpacing.m),
                    ModernCard(
                      child: Row(
                        children: [
                          ShimmerLoading(
                            width: 48,
                            height: 48,
                            shape: BoxShape.circle,
                          ),
                          SizedBox(width: AppSpacing.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShimmerLoading(
                                  width: double.infinity,
                                  height: 16,
                                ),
                                SizedBox(height: AppSpacing.s),
                                ShimmerLoading(
                                  width: 150,
                                  height: 12,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
      floatingActionButton: AnimatedFAB(
        icon: Icons.palette,
        label: 'Design',
        isExtended: true,
        onPressed: () {
          ModernSnackbar.show(
            context: context,
            message: 'Beautiful design! 🎨',
            type: SnackbarType.success,
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.headlineSmall,
        ),
        SizedBox(height: AppSpacing.m),
        child,
      ],
    );
  }
}
