import 'package:flutter/material.dart';
import '../flutter_flow/flutter_flow_theme.dart';
import '../flutter_flow/flutter_flow_icon_button.dart';
import '../components/enhanced_ui_components.dart';
import '../utils/animations.dart';

/// Design System Showcase Page
/// This demonstrates all the new aesthetic improvements
class DesignShowcasePage extends StatefulWidget {
  const DesignShowcasePage({Key? key}) : super(key: key);

  @override
  State<DesignShowcasePage> createState() => _DesignShowcasePageState();
}

class _DesignShowcasePageState extends State<DesignShowcasePage> {
  bool _isLoading = false;
  bool _showShake = false;
  bool _showBounce = false;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.secondaryBackground,
        elevation: 0,
        leading: FlutterFlowIconButton(
          borderColor: Colors.transparent,
          borderRadius: 30,
          buttonSize: 46,
          icon: Icon(
            Icons.arrow_back_rounded,
            color: theme.primaryText,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Design System',
          style: theme.headlineSmall,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Color Palette Section
            SlideInFromBottom(
              child: _buildSection(
                title: 'Color Palette',
                child: Column(
                  children: [
                    _buildColorRow(
                      'Primary',
                      theme.primary,
                      'For main actions',
                    ),
                    SizedBox(height: AppSpacing.s),
                    _buildColorRow(
                      'Secondary',
                      theme.secondary,
                      'For secondary actions',
                    ),
                    SizedBox(height: AppSpacing.s),
                    _buildColorRow(
                      'Tertiary',
                      theme.tertiary,
                      'For highlights',
                    ),
                    SizedBox(height: AppSpacing.s),
                    _buildColorRow(
                      'Success',
                      theme.success,
                      'For success states',
                    ),
                    SizedBox(height: AppSpacing.s),
                    _buildColorRow(
                      'Warning',
                      theme.warning,
                      'For warning states',
                    ),
                    SizedBox(height: AppSpacing.s),
                    _buildColorRow(
                      'Error',
                      theme.error,
                      'For error states',
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Typography Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 100),
              child: _buildSection(
                title: 'Typography',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Display Large', style: theme.displayLarge),
                    SizedBox(height: AppSpacing.s),
                    Text('Headline Large', style: theme.headlineLarge),
                    SizedBox(height: AppSpacing.s),
                    Text('Headline Medium', style: theme.headlineMedium),
                    SizedBox(height: AppSpacing.s),
                    Text('Title Large', style: theme.titleLarge),
                    SizedBox(height: AppSpacing.s),
                    Text('Body Large', style: theme.bodyLarge),
                    SizedBox(height: AppSpacing.s),
                    Text('Label Medium', style: theme.labelMedium),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Buttons Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 200),
              child: _buildSection(
                title: 'Buttons',
                child: Column(
                  children: [
                    GradientButton(
                      text: 'Primary Button',
                      onPressed: () {},
                      icon: Icons.star,
                    ),
                    SizedBox(height: AppSpacing.m),
                    GradientButton(
                      text: 'Loading State',
                      isLoading: _isLoading,
                      onPressed: () {
                        setState(() => _isLoading = true);
                        Future.delayed(Duration(seconds: 2), () {
                          if (mounted) setState(() => _isLoading = false);
                        });
                      },
                    ),
                    SizedBox(height: AppSpacing.m),
                    GradientButton(
                      text: 'Outlined Button',
                      isOutlined: true,
                      onPressed: () {},
                      icon: Icons.favorite_border,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Cards Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 300),
              child: _buildSection(
                title: 'Cards',
                child: Column(
                  children: [
                    ModernCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modern Card',
                            style: theme.titleMedium,
                          ),
                          SizedBox(height: AppSpacing.s),
                          Text(
                            'Enhanced with beautiful shadows and smooth corners',
                            style: theme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.m),
                    ModernCard(
                      useGlassmorphism: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Glassmorphic Card',
                            style: theme.titleMedium,
                          ),
                          SizedBox(height: AppSpacing.s),
                          Text(
                            'With blur effect for modern UI',
                            style: theme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Avatars Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 400),
              child: _buildSection(
                title: 'Avatars',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    PulseAvatar(
                      size: 64,
                      showOnlineStatus: true,
                      isOnline: true,
                    ),
                    PulseAvatar(
                      size: 64,
                      showOnlineStatus: true,
                      isOnline: false,
                    ),
                    PulseAvatar(
                      size: 48,
                    ),
                    PulseAvatar(
                      size: 32,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Status Badges Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 500),
              child: _buildSection(
                title: 'Status Badges',
                child: Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    StatusBadge(
                      text: 'Active',
                      color: theme.success,
                      icon: Icons.check_circle,
                      isPulsing: true,
                    ),
                    StatusBadge(
                      text: 'Pending',
                      color: theme.warning,
                      icon: Icons.access_time,
                    ),
                    StatusBadge(
                      text: 'Offline',
                      color: theme.secondaryText,
                      icon: Icons.circle,
                    ),
                    StatusBadge(
                      text: 'New',
                      color: theme.tertiary,
                      icon: Icons.fiber_new,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Shimmer Loading Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 600),
              child: _buildSection(
                title: 'Loading States',
                child: Column(
                  children: [
                    Row(
                      children: [
                        ShimmerLoading(
                          width: 64,
                          height: 64,
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
                                borderRadius: AppRadius.s,
                              ),
                              SizedBox(height: AppSpacing.s),
                              ShimmerLoading(
                                width: 200,
                                height: 12,
                                borderRadius: AppRadius.s,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Animations Section
            SlideInFromBottom(
              delay: Duration(milliseconds: 700),
              child: _buildSection(
                title: 'Animations',
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            ShakeAnimation(
                              trigger: _showShake,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: theme.error,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.m),
                                ),
                                child: Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                            SizedBox(height: AppSpacing.s),
                            Text('Shake', style: theme.labelSmall),
                          ],
                        ),
                        Column(
                          children: [
                            BounceAnimation(
                              trigger: _showBounce,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: theme.success,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.m),
                                ),
                                child: Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                            SizedBox(height: AppSpacing.s),
                            Text('Bounce', style: theme.labelSmall),
                          ],
                        ),
                        Column(
                          children: [
                            PulseAnimation(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: theme.tertiary,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.m),
                                ),
                                child: Icon(
                                  Icons.notifications,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                            SizedBox(height: AppSpacing.s),
                            Text('Pulse', style: theme.labelSmall),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.m),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _showShake = !_showShake);
                          },
                          child: Text('Trigger Shake'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _showBounce = !_showBounce);
                          },
                          child: Text('Trigger Bounce'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: AppSpacing.xl),

            // Spacing Reference
            SlideInFromBottom(
              delay: Duration(milliseconds: 800),
              child: _buildSection(
                title: 'Spacing System',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSpacingRow('XS', AppSpacing.xs),
                    _buildSpacingRow('S', AppSpacing.s),
                    _buildSpacingRow('M', AppSpacing.m),
                    _buildSpacingRow('L', AppSpacing.l),
                    _buildSpacingRow('XL', AppSpacing.xl),
                    _buildSpacingRow('XXL', AppSpacing.xxl),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Modern design system active!'),
              backgroundColor: theme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.m),
              ),
            ),
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

  Widget _buildColorRow(String name, Color color, String description) {
    final theme = FlutterFlowTheme.of(context);

    return ModernCard(
      padding: EdgeInsets.all(AppSpacing.m),
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.s),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.titleSmall),
                Text(description, style: theme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpacingRow(String label, double spacing) {
    final theme = FlutterFlowTheme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: theme.labelMedium,
            ),
          ),
          Container(
            width: spacing,
            height: 24,
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
          SizedBox(width: AppSpacing.m),
          Text(
            '${spacing.toInt()}px',
            style: theme.bodySmall,
          ),
        ],
      ),
    );
  }
}
