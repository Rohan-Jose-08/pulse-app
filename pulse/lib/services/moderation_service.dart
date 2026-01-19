import 'dart:async';
import 'package:flutter/foundation.dart';
import '../backend/api_service.dart';

/// Report categories for content moderation
enum ReportCategory {
  spam('SPAM', 'Spam', 'Repetitive or promotional content'),
  harassment(
      'HARASSMENT', 'Harassment', 'Bullying, threats, or targeted abuse'),
  hateSpeed('HATE_SPEECH', 'Hate Speech', 'Discrimination based on identity'),
  violence('VIOLENCE', 'Violence', 'Threats or glorification of violence'),
  inappropriate(
      'INAPPROPRIATE', 'Inappropriate', 'Adult content or illegal activity'),
  scam('SCAM', 'Scam', 'Fraudulent or deceptive content'),
  impersonation(
      'IMPERSONATION', 'Impersonation', 'Pretending to be someone else'),
  other('OTHER', 'Other', 'Other violations');

  const ReportCategory(this.value, this.label, this.description);
  final String value;
  final String label;
  final String description;

  static ReportCategory fromValue(String value) {
    return ReportCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReportCategory.other,
    );
  }
}

/// Subcategories for detailed reporting
class ReportSubcategories {
  static const Map<ReportCategory, List<String>> subcategories = {
    ReportCategory.spam: [
      'Repetitive content',
      'Promotional spam',
      'Bot activity',
      'Fake engagement',
    ],
    ReportCategory.harassment: [
      'Bullying',
      'Threats',
      'Stalking',
      'Doxxing',
      'Targeted harassment',
    ],
    ReportCategory.hateSpeed: [
      'Racism',
      'Sexism',
      'Homophobia',
      'Religious hate',
      'Disability discrimination',
    ],
    ReportCategory.violence: [
      'Threats of violence',
      'Graphic content',
      'Glorification of violence',
      'Self-harm',
    ],
    ReportCategory.inappropriate: [
      'Adult content',
      'Nudity',
      'Drug content',
      'Illegal activities',
    ],
    ReportCategory.scam: [
      'Financial scam',
      'Phishing',
      'Fake giveaway',
      'Investment fraud',
    ],
    ReportCategory.impersonation: [
      'Fake identity',
      'Pretending to be someone else',
      'Fake organization',
    ],
    ReportCategory.other: [
      'Copyright violation',
      'Misinformation',
      'Privacy violation',
      'Other',
    ],
  };
}

/// Content report model
class ContentReport {
  final String id;
  final ReportCategory category;
  final String? subcategory;
  final String status;
  final DateTime createdAt;
  final String? resolution;
  final DateTime? reviewedAt;

  ContentReport({
    required this.id,
    required this.category,
    this.subcategory,
    required this.status,
    required this.createdAt,
    this.resolution,
    this.reviewedAt,
  });

  factory ContentReport.fromJson(Map<String, dynamic> json) {
    return ContentReport(
      id: json['id'] ?? '',
      category: ReportCategory.fromValue(json['category'] ?? 'OTHER'),
      subcategory: json['subcategory'],
      status: json['status'] ?? 'PENDING',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      resolution: json['resolution'],
      reviewedAt: json['reviewedAt'] != null
          ? DateTime.tryParse(json['reviewedAt'])
          : null,
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isResolved => status == 'RESOLVED';
  bool get isDismissed => status == 'DISMISSED';
  bool get isUnderReview => status == 'UNDER_REVIEW';
}

/// Blocked user model
class BlockedUser {
  final String id;
  final String? displayName;
  final String? profileImageUrl;
  final DateTime blockedAt;
  final String? reason;

  BlockedUser({
    required this.id,
    this.displayName,
    this.profileImageUrl,
    required this.blockedAt,
    this.reason,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      id: json['id'] ?? '',
      displayName: json['displayName'],
      profileImageUrl: json['profileImageUrl'],
      blockedAt: DateTime.tryParse(json['blockedAt'] ?? '') ?? DateTime.now(),
      reason: json['reason'],
    );
  }
}

/// Muted user model
class MutedUser {
  final String id;
  final String? displayName;
  final String? profileImageUrl;
  final DateTime mutedAt;
  final String? reason;
  final bool muteMessages;
  final bool mutePulses;
  final bool mutePosts;

  MutedUser({
    required this.id,
    this.displayName,
    this.profileImageUrl,
    required this.mutedAt,
    this.reason,
    this.muteMessages = true,
    this.mutePulses = true,
    this.mutePosts = true,
  });

  factory MutedUser.fromJson(Map<String, dynamic> json) {
    return MutedUser(
      id: json['id'] ?? '',
      displayName: json['displayName'],
      profileImageUrl: json['profileImageUrl'],
      mutedAt: DateTime.tryParse(json['mutedAt'] ?? '') ?? DateTime.now(),
      reason: json['reason'],
      muteMessages: json['muteMessages'] ?? true,
      mutePulses: json['mutePulses'] ?? true,
      mutePosts: json['mutePosts'] ?? true,
    );
  }
}

/// User moderation status
class UserModerationStatus {
  final bool isMuted;
  final DateTime? mutedUntil;
  final String? muteReason;
  final bool isSuspended;
  final DateTime? suspendedUntil;
  final String? suspendReason;
  final bool isBanned;
  final String? banReason;
  final bool canCreatePulses;
  final bool canSendMessages;
  final bool canPostHighlights;
  final int warningCount;

  UserModerationStatus({
    this.isMuted = false,
    this.mutedUntil,
    this.muteReason,
    this.isSuspended = false,
    this.suspendedUntil,
    this.suspendReason,
    this.isBanned = false,
    this.banReason,
    this.canCreatePulses = true,
    this.canSendMessages = true,
    this.canPostHighlights = true,
    this.warningCount = 0,
  });

  factory UserModerationStatus.fromJson(Map<String, dynamic> json) {
    return UserModerationStatus(
      isMuted: json['isMuted'] ?? false,
      mutedUntil: json['mutedUntil'] != null
          ? DateTime.tryParse(json['mutedUntil'])
          : null,
      muteReason: json['muteReason'],
      isSuspended: json['isSuspended'] ?? false,
      suspendedUntil: json['suspendedUntil'] != null
          ? DateTime.tryParse(json['suspendedUntil'])
          : null,
      suspendReason: json['suspendReason'],
      isBanned: json['isBanned'] ?? false,
      banReason: json['banReason'],
      canCreatePulses: json['canCreatePulses'] ?? true,
      canSendMessages: json['canSendMessages'] ?? true,
      canPostHighlights: json['canPostHighlights'] ?? true,
      warningCount: json['warningCount'] ?? 0,
    );
  }

  bool get hasRestrictions =>
      isMuted ||
      isSuspended ||
      isBanned ||
      !canCreatePulses ||
      !canSendMessages;
}

/// Moderation action model
class ModerationAction {
  final String id;
  final String actionType;
  final String reason;
  final String? category;
  final int? durationHours;
  final DateTime? expiresAt;
  final String? appealStatus;
  final DateTime createdAt;

  ModerationAction({
    required this.id,
    required this.actionType,
    required this.reason,
    this.category,
    this.durationHours,
    this.expiresAt,
    this.appealStatus,
    required this.createdAt,
  });

  factory ModerationAction.fromJson(Map<String, dynamic> json) {
    return ModerationAction(
      id: json['id'] ?? '',
      actionType: json['actionType'] ?? '',
      reason: json['reason'] ?? '',
      category: json['category'],
      durationHours: json['duration'],
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'])
          : null,
      appealStatus: json['appealStatus'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  bool get canAppeal => appealStatus == null || appealStatus == 'NONE';
}

/// Block status result
class BlockStatus {
  final bool blockedByMe;
  final bool blockedMe;
  final bool isBlocked;

  BlockStatus({
    required this.blockedByMe,
    required this.blockedMe,
    required this.isBlocked,
  });

  factory BlockStatus.fromJson(Map<String, dynamic> json) {
    return BlockStatus(
      blockedByMe: json['blockedByMe'] ?? false,
      blockedMe: json['blockedMe'] ?? false,
      isBlocked: json['isBlocked'] ?? false,
    );
  }
}

/// Muted user IDs for filtering
class MutedUserIds {
  final List<String> mutedForMessages;
  final List<String> mutedForPulses;
  final List<String> mutedForPosts;

  MutedUserIds({
    this.mutedForMessages = const [],
    this.mutedForPulses = const [],
    this.mutedForPosts = const [],
  });

  factory MutedUserIds.fromJson(Map<String, dynamic> json) {
    return MutedUserIds(
      mutedForMessages: List<String>.from(json['mutedForMessages'] ?? []),
      mutedForPulses: List<String>.from(json['mutedForPulses'] ?? []),
      mutedForPosts: List<String>.from(json['mutedForPosts'] ?? []),
    );
  }

  bool isMutedForMessages(String userId) => mutedForMessages.contains(userId);
  bool isMutedForPulses(String userId) => mutedForPulses.contains(userId);
  bool isMutedForPosts(String userId) => mutedForPosts.contains(userId);
}

/// Moderation service for content reporting, blocking, and muting
class ModerationService extends ChangeNotifier {
  static final ModerationService instance = ModerationService._();
  ModerationService._();

  final ApiService _api = ApiService.instance;

  // Cache for blocked/muted users
  List<BlockedUser>? _blockedUsers;
  List<MutedUser>? _mutedUsers;
  MutedUserIds? _mutedUserIds;
  UserModerationStatus? _moderationStatus;
  DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Report content (pulse, message, user, highlight)
  Future<bool> reportContent({
    String? reportedUserId,
    String? reportedPulseId,
    String? reportedMessageId,
    String? reportedHighlightId,
    String? reportedPostId,
    required ReportCategory category,
    String? subcategory,
    String? description,
    List<String>? evidence,
  }) async {
    try {
      final response = await _api.post('/moderation/reports', {
        if (reportedUserId != null) 'reportedUserId': reportedUserId,
        if (reportedPulseId != null) 'reportedPulseId': reportedPulseId,
        if (reportedMessageId != null) 'reportedMessageId': reportedMessageId,
        if (reportedHighlightId != null)
          'reportedHighlightId': reportedHighlightId,
        if (reportedPostId != null) 'reportedPostId': reportedPostId,
        'category': category.value,
        if (subcategory != null) 'subcategory': subcategory,
        if (description != null) 'description': description,
        if (evidence != null) 'evidence': evidence,
      });

      return response['success'] == true;
    } catch (e) {
      debugPrint('Error reporting content: $e');
      return false;
    }
  }

  /// Get user's submitted reports
  Future<List<ContentReport>> getMyReports() async {
    try {
      final response = await _api.get('/moderation/my-reports');
      if (response is List) {
        return response.map((json) => ContentReport.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting reports: $e');
      return [];
    }
  }

  /// Block a user
  Future<bool> blockUser(String userId, {String? reason}) async {
    try {
      final response = await _api.post('/moderation/block', {
        'userId': userId,
        if (reason != null) 'reason': reason,
      });

      if (response['success'] == true) {
        _blockedUsers = null; // Clear cache
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error blocking user: $e');
      return false;
    }
  }

  /// Unblock a user
  Future<bool> unblockUser(String userId) async {
    try {
      await _api.delete('/moderation/block/$userId');
      _blockedUsers = null; // Clear cache
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error unblocking user: $e');
      return false;
    }
  }

  /// Get blocked users list
  Future<List<BlockedUser>> getBlockedUsers({bool forceRefresh = false}) async {
    if (!forceRefresh && _blockedUsers != null && _isCacheValid()) {
      return _blockedUsers!;
    }

    try {
      final response = await _api.get('/moderation/blocked-users');
      if (response is List) {
        _blockedUsers =
            response.map((json) => BlockedUser.fromJson(json)).toList();
        _updateCacheTime();
        return _blockedUsers!;
      }
      return [];
    } catch (e) {
      debugPrint('Error getting blocked users: $e');
      return _blockedUsers ?? [];
    }
  }

  /// Check if user is blocked
  Future<BlockStatus> isUserBlocked(String userId) async {
    try {
      final response = await _api.get('/moderation/is-blocked/$userId');
      return BlockStatus.fromJson(response);
    } catch (e) {
      debugPrint('Error checking block status: $e');
      return BlockStatus(
        blockedByMe: false,
        blockedMe: false,
        isBlocked: false,
      );
    }
  }

  /// Mute a user
  Future<bool> muteUser(
    String userId, {
    String? reason,
    bool muteMessages = true,
    bool mutePulses = true,
    bool mutePosts = true,
  }) async {
    try {
      final response = await _api.post('/moderation/mute', {
        'userId': userId,
        if (reason != null) 'reason': reason,
        'muteMessages': muteMessages,
        'mutePulses': mutePulses,
        'mutePosts': mutePosts,
      });

      if (response['success'] == true) {
        _mutedUsers = null;
        _mutedUserIds = null;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error muting user: $e');
      return false;
    }
  }

  /// Unmute a user
  Future<bool> unmuteUser(String userId) async {
    try {
      await _api.delete('/moderation/mute/$userId');
      _mutedUsers = null;
      _mutedUserIds = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error unmuting user: $e');
      return false;
    }
  }

  /// Get muted users list
  Future<List<MutedUser>> getMutedUsers({bool forceRefresh = false}) async {
    if (!forceRefresh && _mutedUsers != null && _isCacheValid()) {
      return _mutedUsers!;
    }

    try {
      final response = await _api.get('/moderation/muted-users');
      if (response is List) {
        _mutedUsers = response.map((json) => MutedUser.fromJson(json)).toList();
        _updateCacheTime();
        return _mutedUsers!;
      }
      return [];
    } catch (e) {
      debugPrint('Error getting muted users: $e');
      return _mutedUsers ?? [];
    }
  }

  /// Get muted user IDs for filtering content
  Future<MutedUserIds> getMutedUserIds({bool forceRefresh = false}) async {
    if (!forceRefresh && _mutedUserIds != null && _isCacheValid()) {
      return _mutedUserIds!;
    }

    try {
      final response = await _api.get('/moderation/muted-user-ids');
      _mutedUserIds = MutedUserIds.fromJson(response);
      _updateCacheTime();
      return _mutedUserIds!;
    } catch (e) {
      debugPrint('Error getting muted user IDs: $e');
      return _mutedUserIds ?? MutedUserIds();
    }
  }

  /// Get current user's moderation status
  Future<UserModerationStatus> getMyModerationStatus({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _moderationStatus != null && _isCacheValid()) {
      return _moderationStatus!;
    }

    try {
      final response = await _api.get('/moderation/my-status');
      _moderationStatus = UserModerationStatus.fromJson(response);
      _updateCacheTime();
      return _moderationStatus!;
    } catch (e) {
      debugPrint('Error getting moderation status: $e');
      return _moderationStatus ?? UserModerationStatus();
    }
  }

  /// Get moderation actions against current user
  Future<List<ModerationAction>> getMyModerationActions() async {
    try {
      final response = await _api.get('/moderation/my-actions');
      if (response is List) {
        return response.map((json) => ModerationAction.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting moderation actions: $e');
      return [];
    }
  }

  /// Appeal a moderation action
  Future<bool> appealAction(String actionId, String appealNote) async {
    try {
      final response = await _api.post('/moderation/appeal/$actionId', {
        'appealNote': appealNote,
      });
      return response['success'] == true;
    } catch (e) {
      debugPrint('Error appealing action: $e');
      return false;
    }
  }

  /// Check if content is visible (not moderated)
  Future<bool> isContentVisible(String type, String id) async {
    try {
      final response = await _api.get(
        '/moderation/content-visible?type=$type&id=$id',
      );
      return response['visible'] == true;
    } catch (e) {
      debugPrint('Error checking content visibility: $e');
      return true; // Default to visible on error
    }
  }

  /// Filter a list of items by muted users
  List<T> filterMutedContent<T>(
    List<T> items,
    String Function(T) getUserId,
    MutedUserIds mutedIds, {
    bool filterMessages = false,
    bool filterPulses = false,
    bool filterPosts = false,
  }) {
    return items.where((item) {
      final userId = getUserId(item);
      if (filterMessages && mutedIds.isMutedForMessages(userId)) return false;
      if (filterPulses && mutedIds.isMutedForPulses(userId)) return false;
      if (filterPosts && mutedIds.isMutedForPosts(userId)) return false;
      return true;
    }).toList();
  }

  /// Clear all caches
  void clearCache() {
    _blockedUsers = null;
    _mutedUsers = null;
    _mutedUserIds = null;
    _moderationStatus = null;
    _cacheTime = null;
    notifyListeners();
  }

  bool _isCacheValid() {
    return _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration;
  }

  void _updateCacheTime() {
    _cacheTime = DateTime.now();
  }
}
