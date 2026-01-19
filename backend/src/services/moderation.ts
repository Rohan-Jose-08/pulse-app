/**
 * Content Moderation Service
 * 
 * Handles automated content moderation using ML models and manual review workflows.
 * Includes toxicity detection, spam filtering, and content classification.
 */

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// Report categories
export const REPORT_CATEGORIES = {
  SPAM: 'SPAM',
  HARASSMENT: 'HARASSMENT',
  HATE_SPEECH: 'HATE_SPEECH',
  VIOLENCE: 'VIOLENCE',
  INAPPROPRIATE: 'INAPPROPRIATE',
  SCAM: 'SCAM',
  IMPERSONATION: 'IMPERSONATION',
  OTHER: 'OTHER',
} as const;

// Report subcategories by category
export const REPORT_SUBCATEGORIES: Record<string, string[]> = {
  SPAM: ['Repetitive content', 'Promotional spam', 'Bot activity', 'Fake engagement'],
  HARASSMENT: ['Bullying', 'Threats', 'Stalking', 'Doxxing', 'Targeted harassment'],
  HATE_SPEECH: ['Racism', 'Sexism', 'Homophobia', 'Religious hate', 'Disability discrimination'],
  VIOLENCE: ['Threats of violence', 'Graphic content', 'Glorification of violence', 'Self-harm'],
  INAPPROPRIATE: ['Adult content', 'Nudity', 'Drug content', 'Illegal activities'],
  SCAM: ['Financial scam', 'Phishing', 'Fake giveaway', 'Investment fraud'],
  IMPERSONATION: ['Fake identity', 'Pretending to be someone else', 'Fake organization'],
  OTHER: ['Copyright violation', 'Misinformation', 'Privacy violation', 'Other'],
};

// Report status
export const REPORT_STATUS = {
  PENDING: 'PENDING',
  UNDER_REVIEW: 'UNDER_REVIEW',
  RESOLVED: 'RESOLVED',
  DISMISSED: 'DISMISSED',
} as const;

// Report priority
export const REPORT_PRIORITY = {
  LOW: 'LOW',
  NORMAL: 'NORMAL',
  HIGH: 'HIGH',
  URGENT: 'URGENT',
} as const;

// Action types
export const ACTION_TYPES = {
  WARNING: 'WARNING',
  CONTENT_HIDDEN: 'CONTENT_HIDDEN',
  CONTENT_REMOVED: 'CONTENT_REMOVED',
  USER_MUTED: 'USER_MUTED',
  USER_SUSPENDED: 'USER_SUSPENDED',
  USER_BANNED: 'USER_BANNED',
  APPEAL_GRANTED: 'APPEAL_GRANTED',
} as const;

// AI recommendation thresholds
const AI_THRESHOLDS = {
  AUTO_DISMISS: 0.1,      // Below this = likely not a violation
  NEEDS_REVIEW: 0.5,      // Between dismiss and action = needs human review
  AUTO_ACTION: 0.9,       // Above this = auto-take action (hide content)
};

// Keywords for quick detection (supplement to ML)
const TOXICITY_KEYWORDS = [
  // Severe harassment/threats - immediate action
  'kill yourself', 'kys', 'die', 'murder', 'bomb', 'shoot',
];

const SPAM_PATTERNS = [
  /https?:\/\/[^\s]+\.(ru|cn|xyz)/i,  // Suspicious TLDs
  /(?:earn|make)\s*\$?\d+.*(?:day|hour|week)/i,  // Money promises
  /(?:click|visit)\s+(?:here|now|link)/i,  // Clickbait
  /(?:free|win)\s+(?:iphone|bitcoin|crypto|gift)/i,  // Scam patterns
];

/**
 * Analyze text content for moderation
 */
export async function analyzeContent(text: string): Promise<{
  toxicityScore: number;
  spamScore: number;
  violenceScore: number;
  adultScore: number;
  categories: string[];
  recommendation: string;
}> {
  // Quick keyword check first
  const lowerText = text.toLowerCase();
  let toxicityScore = 0;
  let spamScore = 0;
  let violenceScore = 0;
  let adultScore = 0;
  const categories: string[] = [];

  // Check for toxicity keywords
  for (const keyword of TOXICITY_KEYWORDS) {
    if (lowerText.includes(keyword)) {
      toxicityScore = Math.max(toxicityScore, 0.9);
      violenceScore = Math.max(violenceScore, 0.8);
      categories.push('VIOLENCE', 'HARASSMENT');
      break;
    }
  }

  // Check for spam patterns
  for (const pattern of SPAM_PATTERNS) {
    if (pattern.test(text)) {
      spamScore = Math.max(spamScore, 0.8);
      categories.push('SPAM');
      break;
    }
  }

  // Call ML service for detailed analysis
  try {
    const mlResult = await callMLModerationService(text);
    toxicityScore = Math.max(toxicityScore, mlResult.toxicityScore);
    spamScore = Math.max(spamScore, mlResult.spamScore);
    violenceScore = Math.max(violenceScore, mlResult.violenceScore);
    adultScore = Math.max(adultScore, mlResult.adultScore);
    categories.push(...mlResult.categories.filter(c => !categories.includes(c)));
  } catch (error) {
    console.error('ML moderation service error:', error);
    // Fall back to keyword-based detection
  }

  // Determine recommendation based on highest score
  const maxScore = Math.max(toxicityScore, spamScore, violenceScore, adultScore);
  let recommendation: string;
  
  if (maxScore < AI_THRESHOLDS.AUTO_DISMISS) {
    recommendation = 'AUTO_DISMISS';
  } else if (maxScore >= AI_THRESHOLDS.AUTO_ACTION) {
    recommendation = 'AUTO_ACTION';
  } else {
    recommendation = 'NEEDS_REVIEW';
  }

  return {
    toxicityScore,
    spamScore,
    violenceScore,
    adultScore,
    categories: [...new Set(categories)],
    recommendation,
  };
}

/**
 * Call the ML moderation service
 */
async function callMLModerationService(text: string): Promise<{
  toxicityScore: number;
  spamScore: number;
  violenceScore: number;
  adultScore: number;
  categories: string[];
}> {
  const mlServiceUrl = process.env.ML_SERVICE_URL || 'http://localhost:5001';
  
  try {
    const response = await fetch(`${mlServiceUrl}/api/moderate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    });

    if (!response.ok) {
      throw new Error(`ML service returned ${response.status}`);
    }

    return await response.json();
  } catch (error) {
    // Return neutral scores if ML service is unavailable
    console.warn('ML moderation service unavailable, using fallback');
    return {
      toxicityScore: 0,
      spamScore: 0,
      violenceScore: 0,
      adultScore: 0,
      categories: [],
    };
  }
}

/**
 * Create a content report
 */
export async function createReport(params: {
  reporterId: string;
  reportedUserId?: string;
  reportedPulseId?: string;
  reportedMessageId?: string;
  reportedHighlightId?: string;
  reportedPostId?: string;
  category: string;
  subcategory?: string;
  description?: string;
  evidence?: string[];
}): Promise<any> {
  console.log('createReport called with params:', JSON.stringify(params, null, 2));
  
  // Validate that exactly one target is specified
  const targets = [
    params.reportedUserId,
    params.reportedPulseId,
    params.reportedMessageId,
    params.reportedHighlightId,
    params.reportedPostId,
  ].filter(Boolean);

  console.log('Targets found:', targets.length, targets);

  if (targets.length !== 1) {
    throw new Error(`Exactly one report target must be specified. Found: ${targets.length}`);
  }

  // Get content text for AI analysis
  let contentText = params.description || '';
  
  if (params.reportedPulseId) {
    const pulse = await prisma.pulse.findUnique({
      where: { id: params.reportedPulseId },
      select: { title: true, description: true },
    });
    if (pulse) {
      contentText = `${pulse.title} ${pulse.description} ${contentText}`;
    }
  } else if (params.reportedMessageId) {
    const message = await prisma.message.findUnique({
      where: { id: params.reportedMessageId },
      select: { text: true },
    });
    if (message?.text) {
      contentText = `${message.text} ${contentText}`;
    }
  }

  // Run AI analysis
  const aiAnalysis = await analyzeContent(contentText);
  console.log('AI analysis result:', aiAnalysis);
  
  // Determine priority based on category and AI analysis
  let priority: string = REPORT_PRIORITY.NORMAL;
  if (aiAnalysis.recommendation === 'AUTO_ACTION') {
    priority = REPORT_PRIORITY.HIGH;
  }
  if (['VIOLENCE', 'HARASSMENT'].includes(params.category) && aiAnalysis.toxicityScore > 0.7) {
    priority = REPORT_PRIORITY.URGENT;
  }

  console.log('Creating report with data:', {
    reporterId: params.reporterId,
    reportedUserId: params.reportedUserId,
    reportedPulseId: params.reportedPulseId,
    reportedMessageId: params.reportedMessageId,
    reportedHighlightId: params.reportedHighlightId,
    reportedPostId: params.reportedPostId,
    category: params.category,
    priority,
  });

  try {
    const report = await prisma.contentReport.create({
      data: {
        reporterId: params.reporterId,
        reportedUserId: params.reportedUserId || undefined,
        reportedPulseId: params.reportedPulseId || undefined,
        reportedMessageId: params.reportedMessageId || undefined,
        reportedHighlightId: params.reportedHighlightId || undefined,
        reportedPostId: params.reportedPostId || undefined,
        category: params.category,
        subcategory: params.subcategory || undefined,
        description: params.description || undefined,
        evidence: params.evidence || [],
        priority,
        aiAnalyzed: true,
        aiConfidenceScore: Math.max(
          aiAnalysis.toxicityScore,
          aiAnalysis.spamScore,
          aiAnalysis.violenceScore,
          aiAnalysis.adultScore
        ),
        aiCategories: aiAnalysis.categories,
        aiRecommendation: aiAnalysis.recommendation,
      },
    });
    console.log('Report created successfully:', report.id);
    
    // Auto-action if confidence is very high
    if (aiAnalysis.recommendation === 'AUTO_ACTION') {
      await handleAutoModeration(report);
    }
    
    return report;
  } catch (prismaError: any) {
    console.error('Prisma error creating report:', prismaError?.message || prismaError);
    console.error('Prisma error code:', prismaError?.code);
    throw prismaError;
  }
}

/**
 * Handle automated moderation action
 */
async function handleAutoModeration(report: any): Promise<void> {
  // Hide content immediately for high-confidence violations
  if (report.reportedPulseId) {
    await hideContent('pulse', report.reportedPulseId, 'AUTO_MODERATION', report.aiCategories.join(', '));
  } else if (report.reportedMessageId) {
    await hideContent('message', report.reportedMessageId, 'AUTO_MODERATION', report.aiCategories.join(', '));
  } else if (report.reportedHighlightId) {
    await hideContent('highlight', report.reportedHighlightId, 'AUTO_MODERATION', report.aiCategories.join(', '));
  }

  // Create moderation action record
  await prisma.moderationAction.create({
    data: {
      targetUserId: report.reportedUserId,
      targetPulseId: report.reportedPulseId,
      targetMessageId: report.reportedMessageId,
      targetHighlightId: report.reportedHighlightId,
      actionType: ACTION_TYPES.CONTENT_HIDDEN,
      reason: 'Automated moderation - content flagged for review',
      category: report.category,
      performedBy: 'SYSTEM',
      isAutomated: true,
      relatedReportId: report.id,
    },
  });

  // Update report status
  await prisma.contentReport.update({
    where: { id: report.id },
    data: { status: REPORT_STATUS.UNDER_REVIEW },
  });

  // Log the action
  await logModerationAction({
    action: 'AUTO_HIDE_CONTENT',
    targetType: report.reportedPulseId ? 'PULSE' : 
                report.reportedMessageId ? 'MESSAGE' : 
                report.reportedHighlightId ? 'HIGHLIGHT' : 'USER',
    targetId: report.reportedPulseId || report.reportedMessageId || 
              report.reportedHighlightId || report.reportedUserId,
    details: {
      reportId: report.id,
      aiConfidence: report.aiConfidenceScore,
      categories: report.aiCategories,
    },
  });
}

/**
 * Hide content from public view
 */
export async function hideContent(
  type: 'pulse' | 'message' | 'highlight' | 'post',
  id: string,
  hiddenBy: string,
  reason?: string
): Promise<void> {
  const field = `${type}Id`;
  
  await prisma.contentModerationFlag.upsert({
    where: { [field]: id } as any,
    create: {
      [field]: id,
      isHidden: true,
      reason,
      hiddenAt: new Date(),
      hiddenBy,
    },
    update: {
      isHidden: true,
      reason,
      hiddenAt: new Date(),
      hiddenBy,
    },
  });
}

/**
 * Remove content (soft delete)
 */
export async function removeContent(
  type: 'pulse' | 'message' | 'highlight' | 'post',
  id: string,
  removedBy: string,
  reason?: string
): Promise<void> {
  const field = `${type}Id`;
  
  await prisma.contentModerationFlag.upsert({
    where: { [field]: id } as any,
    create: {
      [field]: id,
      isRemoved: true,
      reason,
      removedAt: new Date(),
      removedBy,
    },
    update: {
      isRemoved: true,
      reason,
      removedAt: new Date(),
      removedBy,
    },
  });
}

/**
 * Restore hidden/removed content
 */
export async function restoreContent(
  type: 'pulse' | 'message' | 'highlight' | 'post',
  id: string
): Promise<void> {
  const field = `${type}Id`;
  
  await prisma.contentModerationFlag.updateMany({
    where: { [field]: id } as any,
    data: {
      isHidden: false,
      isRemoved: false,
    },
  });
}

/**
 * Check if content is visible (not hidden or removed)
 */
export async function isContentVisible(
  type: 'pulse' | 'message' | 'highlight' | 'post',
  id: string
): Promise<boolean> {
  const field = `${type}Id`;
  
  const flag = await prisma.contentModerationFlag.findFirst({
    where: { [field]: id } as any,
  });
  
  if (!flag) return true;
  return !flag.isHidden && !flag.isRemoved;
}

/**
 * Get user moderation status
 */
export async function getUserModerationStatus(userId: string): Promise<any> {
  let status = await prisma.userModerationStatus.findUnique({
    where: { userId },
  });

  if (!status) {
    status = await prisma.userModerationStatus.create({
      data: { userId },
    });
  }

  // Check if temporary restrictions have expired
  const now = new Date();
  let needsUpdate = false;
  const updates: any = {};

  if (status.isMuted && status.mutedUntil && status.mutedUntil < now) {
    updates.isMuted = false;
    updates.mutedUntil = null;
    needsUpdate = true;
  }

  if (status.isSuspended && status.suspendedUntil && status.suspendedUntil < now) {
    updates.isSuspended = false;
    updates.suspendedUntil = null;
    needsUpdate = true;
  }

  if (needsUpdate) {
    status = await prisma.userModerationStatus.update({
      where: { userId },
      data: updates,
    });
  }

  return status;
}

/**
 * Warn a user
 */
export async function warnUser(
  userId: string,
  reason: string,
  performedBy: string,
  reportId?: string
): Promise<void> {
  // Update warning count
  await prisma.userModerationStatus.upsert({
    where: { userId },
    create: {
      userId,
      warningCount: 1,
      lastWarningAt: new Date(),
    },
    update: {
      warningCount: { increment: 1 },
      lastWarningAt: new Date(),
    },
  });

  // Create action record
  await prisma.moderationAction.create({
    data: {
      targetUserId: userId,
      actionType: ACTION_TYPES.WARNING,
      reason,
      performedBy,
      relatedReportId: reportId,
    },
  });

  // Log
  await logModerationAction({
    adminUserId: performedBy !== 'SYSTEM' ? performedBy : undefined,
    action: 'WARN_USER',
    targetType: 'USER',
    targetId: userId,
    details: { reason, reportId },
  });
}

/**
 * Mute a user (prevent sending messages)
 */
export async function muteUser(
  userId: string,
  reason: string,
  durationHours: number | null,
  performedBy: string,
  reportId?: string
): Promise<void> {
  const mutedUntil = durationHours 
    ? new Date(Date.now() + durationHours * 60 * 60 * 1000)
    : null;

  await prisma.userModerationStatus.upsert({
    where: { userId },
    create: {
      userId,
      isMuted: true,
      mutedUntil,
      muteReason: reason,
      canSendMessages: false,
    },
    update: {
      isMuted: true,
      mutedUntil,
      muteReason: reason,
      canSendMessages: false,
    },
  });

  await prisma.moderationAction.create({
    data: {
      targetUserId: userId,
      actionType: ACTION_TYPES.USER_MUTED,
      reason,
      duration: durationHours,
      expiresAt: mutedUntil,
      performedBy,
      relatedReportId: reportId,
    },
  });

  await logModerationAction({
    adminUserId: performedBy !== 'SYSTEM' ? performedBy : undefined,
    action: 'MUTE_USER',
    targetType: 'USER',
    targetId: userId,
    details: { reason, durationHours, reportId },
  });
}

/**
 * Suspend a user (temporary account restriction)
 */
export async function suspendUser(
  userId: string,
  reason: string,
  durationHours: number,
  performedBy: string,
  reportId?: string
): Promise<void> {
  const suspendedUntil = new Date(Date.now() + durationHours * 60 * 60 * 1000);

  await prisma.userModerationStatus.upsert({
    where: { userId },
    create: {
      userId,
      isSuspended: true,
      suspendedUntil,
      suspendReason: reason,
    },
    update: {
      isSuspended: true,
      suspendedUntil,
      suspendReason: reason,
    },
  });

  await prisma.moderationAction.create({
    data: {
      targetUserId: userId,
      actionType: ACTION_TYPES.USER_SUSPENDED,
      reason,
      duration: durationHours,
      expiresAt: suspendedUntil,
      performedBy,
      relatedReportId: reportId,
    },
  });

  await logModerationAction({
    adminUserId: performedBy !== 'SYSTEM' ? performedBy : undefined,
    action: 'SUSPEND_USER',
    targetType: 'USER',
    targetId: userId,
    details: { reason, durationHours, reportId },
  });
}

/**
 * Ban a user (permanent)
 */
export async function banUser(
  userId: string,
  reason: string,
  performedBy: string,
  reportId?: string
): Promise<void> {
  await prisma.userModerationStatus.upsert({
    where: { userId },
    create: {
      userId,
      isBanned: true,
      bannedAt: new Date(),
      banReason: reason,
    },
    update: {
      isBanned: true,
      bannedAt: new Date(),
      banReason: reason,
    },
  });

  await prisma.moderationAction.create({
    data: {
      targetUserId: userId,
      actionType: ACTION_TYPES.USER_BANNED,
      reason,
      performedBy,
      relatedReportId: reportId,
    },
  });

  await logModerationAction({
    adminUserId: performedBy !== 'SYSTEM' ? performedBy : undefined,
    action: 'BAN_USER',
    targetType: 'USER',
    targetId: userId,
    details: { reason, reportId },
  });
}

/**
 * Reduce user trust score (affects automated moderation thresholds)
 */
export async function reduceTrustScore(userId: string, amount: number): Promise<void> {
  const status = await prisma.userModerationStatus.findUnique({
    where: { userId },
  });

  const currentScore = status?.trustScore ?? 1.0;
  const newScore = Math.max(0, currentScore - amount);

  await prisma.userModerationStatus.upsert({
    where: { userId },
    create: { userId, trustScore: newScore },
    update: { trustScore: newScore },
  });
}

/**
 * Log moderation action for audit trail
 */
export async function logModerationAction(params: {
  adminUserId?: string;
  action: string;
  targetType: string;
  targetId: string;
  details?: any;
  ipAddress?: string;
  userAgent?: string;
}): Promise<void> {
  await prisma.moderationAuditLog.create({
    data: {
      adminUserId: params.adminUserId,
      action: params.action,
      targetType: params.targetType,
      targetId: params.targetId,
      details: params.details,
      ipAddress: params.ipAddress,
      userAgent: params.userAgent,
    },
  });
}

/**
 * Get pending reports for admin review
 */
export async function getPendingReports(params: {
  status?: string;
  priority?: string;
  category?: string;
  page?: number;
  limit?: number;
}): Promise<{ reports: any[]; total: number }> {
  const { status = 'PENDING', priority, category, page = 1, limit = 20 } = params;

  const where: any = { status };
  if (priority) where.priority = priority;
  if (category) where.category = category;

  const [reports, total] = await Promise.all([
    prisma.contentReport.findMany({
      where,
      orderBy: [
        { priority: 'desc' },
        { createdAt: 'asc' },
      ],
      skip: (page - 1) * limit,
      take: limit,
    }),
    prisma.contentReport.count({ where }),
  ]);

  return { reports, total };
}

/**
 * Resolve a report
 */
export async function resolveReport(
  reportId: string,
  resolution: string,
  actionTaken: string | null,
  resolutionNote: string | null,
  reviewedBy: string
): Promise<any> {
  return prisma.contentReport.update({
    where: { id: reportId },
    data: {
      status: REPORT_STATUS.RESOLVED,
      resolution,
      actionTaken,
      resolutionNote,
      reviewedBy,
      reviewedAt: new Date(),
    },
  });
}

/**
 * Dismiss a report
 */
export async function dismissReport(
  reportId: string,
  resolutionNote: string | null,
  reviewedBy: string
): Promise<any> {
  return prisma.contentReport.update({
    where: { id: reportId },
    data: {
      status: REPORT_STATUS.DISMISSED,
      resolution: 'NO_VIOLATION',
      resolutionNote,
      reviewedBy,
      reviewedAt: new Date(),
    },
  });
}

/**
 * Get moderation statistics
 */
export async function getModerationStats(): Promise<any> {
  const now = new Date();
  const last24h = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const last7d = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

  const [
    pendingReports,
    urgentReports,
    reportsLast24h,
    reportsLast7d,
    actionsLast24h,
    actionsLast7d,
    autoModeratedLast24h,
    suspendedUsers,
    bannedUsers,
  ] = await Promise.all([
    prisma.contentReport.count({ where: { status: 'PENDING' } }),
    prisma.contentReport.count({ where: { status: 'PENDING', priority: 'URGENT' } }),
    prisma.contentReport.count({ where: { createdAt: { gte: last24h } } }),
    prisma.contentReport.count({ where: { createdAt: { gte: last7d } } }),
    prisma.moderationAction.count({ where: { createdAt: { gte: last24h } } }),
    prisma.moderationAction.count({ where: { createdAt: { gte: last7d } } }),
    prisma.moderationAction.count({ where: { createdAt: { gte: last24h }, isAutomated: true } }),
    prisma.userModerationStatus.count({ where: { isSuspended: true } }),
    prisma.userModerationStatus.count({ where: { isBanned: true } }),
  ]);

  return {
    pendingReports,
    urgentReports,
    reportsLast24h,
    reportsLast7d,
    actionsLast24h,
    actionsLast7d,
    autoModeratedLast24h,
    suspendedUsers,
    bannedUsers,
  };
}
