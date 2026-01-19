/// Moderation module exports
///
/// This module provides comprehensive content moderation and safety features
/// including:
/// - Content reporting
/// - User blocking and muting
/// - Admin moderation dashboard
/// - Event organizer moderation tools
/// - Automated ML-based content moderation

// Services
export 'package:pulse/services/moderation_service.dart';
export 'package:pulse/services/admin_moderation_service.dart';

// User-facing widgets
export 'package:pulse/widgets/moderation/report_content_dialog.dart';
export 'package:pulse/widgets/moderation/user_actions_sheet.dart';
export 'package:pulse/widgets/moderation/moderation_status_banner.dart';
export 'package:pulse/widgets/moderation/pulse_moderation_sheet.dart';

// Settings pages
export 'package:pulse/pages/settings/blocked_muted_users_page.dart';

// Admin pages
export 'package:pulse/pages/admin/admin_moderation_dashboard.dart';
export 'package:pulse/pages/admin/admin_reports_page.dart';
export 'package:pulse/pages/admin/admin_appeals_page.dart';
export 'package:pulse/pages/admin/admin_audit_log_page.dart';
