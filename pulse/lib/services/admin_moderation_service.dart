import 'dart:convert';
import 'package:http/http.dart' as http;
import '../flutter_flow/flutter_flow_util.dart';

/// Admin-specific moderation service
class AdminModerationService {
  static final AdminModerationService instance = AdminModerationService._();
  AdminModerationService._();

  final String _baseUrl = 'http://localhost:3000/api/admin/moderation';

  Future<String?> _getAuthToken() async {
    // Get from your auth service
    return null;
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get moderation statistics
  Future<ModerationStats?> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/stats'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ModerationStats.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error fetching moderation stats: $e');
    }
    return null;
  }

  /// Get moderation analytics
  Future<ModerationAnalytics?> getAnalytics({int days = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics?days=$days'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ModerationAnalytics.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
    }
    return null;
  }

  /// Get pending reports
  Future<List<AdminReport>> getPendingReports(
      {int page = 1, int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/reports?status=PENDING&page=$page&limit=$limit'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reports = data['reports'] as List;
        return reports.map((r) => AdminReport.fromJson(r)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
    }
    return [];
  }

  /// Get report details
  Future<AdminReport?> getReportDetails(String reportId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/reports/$reportId'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AdminReport.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error fetching report details: $e');
    }
    return null;
  }

  /// Resolve a report
  Future<bool> resolveReport({
    required String reportId,
    required String resolution,
    required String action,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/reports/$reportId/resolve'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'resolution': resolution,
          'action': action,
          if (notes != null) 'notes': notes,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error resolving report: $e');
      return false;
    }
  }

  /// Hide content
  Future<bool> hideContent({
    required String contentType,
    required String contentId,
    required String reason,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/content/hide'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'contentType': contentType,
          'contentId': contentId,
          'reason': reason,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error hiding content: $e');
      return false;
    }
  }

  /// Remove content permanently
  Future<bool> removeContent({
    required String contentType,
    required String contentId,
    required String reason,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/content/remove'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'contentType': contentType,
          'contentId': contentId,
          'reason': reason,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error removing content: $e');
      return false;
    }
  }

  /// Issue a warning to a user
  Future<bool> warnUser({
    required String userId,
    required String reason,
    String? message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users/$userId/warn'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'reason': reason,
          if (message != null) 'message': message,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error warning user: $e');
      return false;
    }
  }

  /// Mute a user
  Future<bool> muteUser({
    required String userId,
    required String reason,
    required int durationHours,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users/$userId/mute'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'reason': reason,
          'durationHours': durationHours,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error muting user: $e');
      return false;
    }
  }

  /// Suspend a user
  Future<bool> suspendUser({
    required String userId,
    required String reason,
    required int durationDays,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users/$userId/suspend'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'reason': reason,
          'durationDays': durationDays,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error suspending user: $e');
      return false;
    }
  }

  /// Ban a user permanently
  Future<bool> banUser({
    required String userId,
    required String reason,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/users/$userId/ban'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'reason': reason,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error banning user: $e');
      return false;
    }
  }

  /// Get user moderation history
  Future<UserModerationHistory?> getUserHistory(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/users/$userId/history'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UserModerationHistory.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error fetching user history: $e');
    }
    return null;
  }

  /// Get pending appeals
  Future<List<ModerationAppeal>> getPendingAppeals() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/appeals?status=PENDING'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final appeals = data['appeals'] as List;
        return appeals.map((a) => ModerationAppeal.fromJson(a)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching appeals: $e');
    }
    return [];
  }

  /// Resolve an appeal
  Future<bool> resolveAppeal({
    required String appealId,
    required String decision,
    required String reason,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/appeals/$appealId/resolve'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'decision': decision,
          'reason': reason,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error resolving appeal: $e');
      return false;
    }
  }

  /// Get audit log
  Future<List<AuditLogEntry>> getAuditLog(
      {int page = 1, int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/audit-log?page=$page&limit=$limit'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final entries = data['entries'] as List;
        return entries.map((e) => AuditLogEntry.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching audit log: $e');
    }
    return [];
  }
}

/// Moderation statistics
class ModerationStats {
  final int pendingReports;
  final int resolvedToday;
  final int activeWarnings;
  final int suspendedUsers;
  final int bannedUsers;
  final int pendingAppeals;
  final double avgResolutionTime;

  ModerationStats({
    required this.pendingReports,
    required this.resolvedToday,
    required this.activeWarnings,
    required this.suspendedUsers,
    required this.bannedUsers,
    required this.pendingAppeals,
    required this.avgResolutionTime,
  });

  factory ModerationStats.fromJson(Map<String, dynamic> json) {
    return ModerationStats(
      pendingReports: json['pendingReports'] ?? 0,
      resolvedToday: json['resolvedToday'] ?? 0,
      activeWarnings: json['activeWarnings'] ?? 0,
      suspendedUsers: json['suspendedUsers'] ?? 0,
      bannedUsers: json['bannedUsers'] ?? 0,
      pendingAppeals: json['pendingAppeals'] ?? 0,
      avgResolutionTime: (json['avgResolutionTime'] ?? 0).toDouble(),
    );
  }
}

/// Moderation analytics
class ModerationAnalytics {
  final List<DailyReportCount> reportsByDay;
  final Map<String, int> reportsByCategory;
  final Map<String, int> actionsByType;
  final double autoModerationRate;

  ModerationAnalytics({
    required this.reportsByDay,
    required this.reportsByCategory,
    required this.actionsByType,
    required this.autoModerationRate,
  });

  factory ModerationAnalytics.fromJson(Map<String, dynamic> json) {
    final reportsByDay = (json['reportsByDay'] as List? ?? [])
        .map((d) => DailyReportCount.fromJson(d))
        .toList();

    return ModerationAnalytics(
      reportsByDay: reportsByDay,
      reportsByCategory: Map<String, int>.from(json['reportsByCategory'] ?? {}),
      actionsByType: Map<String, int>.from(json['actionsByType'] ?? {}),
      autoModerationRate: (json['autoModerationRate'] ?? 0).toDouble(),
    );
  }
}

class DailyReportCount {
  final DateTime date;
  final int count;

  DailyReportCount({required this.date, required this.count});

  factory DailyReportCount.fromJson(Map<String, dynamic> json) {
    return DailyReportCount(
      date: DateTime.parse(json['date']),
      count: json['count'] ?? 0,
    );
  }
}

/// Admin report model with full details
class AdminReport {
  final String id;
  final String reporterId;
  final String? reporterName;
  final String? reporterAvatar;
  final String contentType;
  final String contentId;
  final String category;
  final String? subcategory;
  final String? description;
  final String status;
  final DateTime createdAt;
  final double? aiToxicityScore;
  final double? aiSpamScore;
  final bool? aiRecommendedAction;
  final String? resolution;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final Map<String, dynamic>? contentData;
  final Map<String, dynamic>? reportedUserData;

  AdminReport({
    required this.id,
    required this.reporterId,
    this.reporterName,
    this.reporterAvatar,
    required this.contentType,
    required this.contentId,
    required this.category,
    this.subcategory,
    this.description,
    required this.status,
    required this.createdAt,
    this.aiToxicityScore,
    this.aiSpamScore,
    this.aiRecommendedAction,
    this.resolution,
    this.resolvedBy,
    this.resolvedAt,
    this.contentData,
    this.reportedUserData,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    return AdminReport(
      id: json['id'],
      reporterId: json['reporterId'],
      reporterName: json['reporter']?['displayName'],
      reporterAvatar: json['reporter']?['profileImageUrl'],
      contentType: json['contentType'],
      contentId: json['contentId'],
      category: json['category'],
      subcategory: json['subcategory'],
      description: json['description'],
      status: json['status'],
      createdAt: DateTime.parse(json['createdAt']),
      aiToxicityScore: json['aiToxicityScore']?.toDouble(),
      aiSpamScore: json['aiSpamScore']?.toDouble(),
      aiRecommendedAction: json['aiRecommendedAction'],
      resolution: json['resolution'],
      resolvedBy: json['resolvedBy'],
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'])
          : null,
      contentData: json['contentData'],
      reportedUserData: json['reportedUserData'],
    );
  }

  bool get isHighPriority =>
      (aiToxicityScore ?? 0) > 0.8 ||
      category == 'VIOLENCE' ||
      category == 'ILLEGAL_ACTIVITY';

  Color get priorityColor {
    if (isHighPriority) return const Color(0xFFEF4444);
    if ((aiToxicityScore ?? 0) > 0.5) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }
}

/// User moderation history
class UserModerationHistory {
  final String userId;
  final String? displayName;
  final String? email;
  final int trustScore;
  final String status;
  final int totalReports;
  final int confirmedViolations;
  final List<ModerationActionEntry> actions;

  UserModerationHistory({
    required this.userId,
    this.displayName,
    this.email,
    required this.trustScore,
    required this.status,
    required this.totalReports,
    required this.confirmedViolations,
    required this.actions,
  });

  factory UserModerationHistory.fromJson(Map<String, dynamic> json) {
    final actions = (json['actions'] as List? ?? [])
        .map((a) => ModerationActionEntry.fromJson(a))
        .toList();

    return UserModerationHistory(
      userId: json['userId'],
      displayName: json['displayName'],
      email: json['email'],
      trustScore: json['trustScore'] ?? 100,
      status: json['status'] ?? 'GOOD_STANDING',
      totalReports: json['totalReports'] ?? 0,
      confirmedViolations: json['confirmedViolations'] ?? 0,
      actions: actions,
    );
  }
}

class ModerationActionEntry {
  final String id;
  final String actionType;
  final String reason;
  final DateTime createdAt;
  final String? adminName;
  final DateTime? expiresAt;

  ModerationActionEntry({
    required this.id,
    required this.actionType,
    required this.reason,
    required this.createdAt,
    this.adminName,
    this.expiresAt,
  });

  factory ModerationActionEntry.fromJson(Map<String, dynamic> json) {
    return ModerationActionEntry(
      id: json['id'],
      actionType: json['actionType'],
      reason: json['reason'],
      createdAt: DateTime.parse(json['createdAt']),
      adminName: json['admin']?['displayName'],
      expiresAt:
          json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
    );
  }
}

/// Moderation appeal
class ModerationAppeal {
  final String id;
  final String userId;
  final String? userName;
  final String actionId;
  final String actionType;
  final String appealReason;
  final String status;
  final DateTime createdAt;
  final String? resolution;
  final DateTime? resolvedAt;

  ModerationAppeal({
    required this.id,
    required this.userId,
    this.userName,
    required this.actionId,
    required this.actionType,
    required this.appealReason,
    required this.status,
    required this.createdAt,
    this.resolution,
    this.resolvedAt,
  });

  factory ModerationAppeal.fromJson(Map<String, dynamic> json) {
    return ModerationAppeal(
      id: json['id'],
      userId: json['userId'],
      userName: json['user']?['displayName'],
      actionId: json['actionId'],
      actionType: json['action']?['actionType'] ?? 'UNKNOWN',
      appealReason: json['appealReason'] ?? '',
      status: json['status'],
      createdAt: DateTime.parse(json['createdAt']),
      resolution: json['resolution'],
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'])
          : null,
    );
  }
}

/// Audit log entry
class AuditLogEntry {
  final String id;
  final String adminId;
  final String? adminName;
  final String action;
  final String? targetUserId;
  final String? targetUserName;
  final String? contentType;
  final String? contentId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  AuditLogEntry({
    required this.id,
    required this.adminId,
    this.adminName,
    required this.action,
    this.targetUserId,
    this.targetUserName,
    this.contentType,
    this.contentId,
    this.details,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'],
      adminId: json['adminId'],
      adminName: json['admin']?['displayName'],
      action: json['action'],
      targetUserId: json['targetUserId'],
      targetUserName: json['targetUser']?['displayName'],
      contentType: json['contentType'],
      contentId: json['contentId'],
      details: json['details'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
