/**
 * Admin Moderation Routes
 * 
 * Handles administrative moderation tasks including report review,
 * user management, and moderation dashboard functionality.
 */

import { Router, Request, Response, NextFunction } from 'express';
import { PrismaClient } from '@prisma/client';
import { getAuth } from 'firebase-admin/auth';
import {
  getPendingReports,
  resolveReport,
  dismissReport,
  warnUser,
  muteUser,
  suspendUser,
  banUser,
  hideContent,
  removeContent,
  restoreContent,
  getModerationStats,
  logModerationAction,
  reduceTrustScore,
} from '../services/moderation';

const router = Router();
const prisma = new PrismaClient();

// Helper to get authenticated admin user
async function getAuthenticatedAdmin(req: Request): Promise<{
  user: { id: string; firebaseUid: string };
  admin: any;
} | null> {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(token);
    const user = await prisma.user.findUnique({
      where: { firebaseUid: decodedToken.uid },
      select: { id: true, firebaseUid: true },
    });

    if (!user) return null;

    const admin = await prisma.adminUser.findUnique({
      where: { userId: user.id },
    });

    if (!admin || !admin.isActive) return null;

    return { user, admin };
  } catch {
    return null;
  }
}

// Admin authentication middleware
async function requireAdmin(req: Request, res: Response, next: NextFunction) {
  const auth = await getAuthenticatedAdmin(req);
  if (!auth) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  (req as any).adminAuth = auth;
  next();
}

// Permission check middleware factory
function requirePermission(permission: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const auth = (req as any).adminAuth;
    if (!auth?.admin[permission]) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

// ============================================================================
// DASHBOARD & STATS
// ============================================================================

/**
 * GET /api/admin/moderation/stats
 * Get moderation dashboard statistics
 */
router.get('/stats', requireAdmin, requirePermission('canViewReports'), async (req: Request, res: Response) => {
  try {
    const stats = await getModerationStats();
    res.json(stats);
  } catch (error) {
    console.error('Error fetching moderation stats:', error);
    res.status(500).json({ error: 'Failed to fetch statistics' });
  }
});

/**
 * GET /api/admin/moderation/analytics
 * Get detailed moderation analytics
 */
router.get('/analytics', requireAdmin, requirePermission('canViewAnalytics'), async (req: Request, res: Response) => {
  try {
    const { period = '7d' } = req.query;

    let startDate: Date;
    switch (period) {
      case '24h':
        startDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
        break;
      case '7d':
        startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
        break;
      case '30d':
        startDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        break;
      default:
        startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    }

    // Get reports by category
    const reportsByCategory = await prisma.contentReport.groupBy({
      by: ['category'],
      where: { createdAt: { gte: startDate } },
      _count: { id: true },
    });

    // Get reports by status
    const reportsByStatus = await prisma.contentReport.groupBy({
      by: ['status'],
      where: { createdAt: { gte: startDate } },
      _count: { id: true },
    });

    // Get actions by type
    const actionsByType = await prisma.moderationAction.groupBy({
      by: ['actionType'],
      where: { createdAt: { gte: startDate } },
      _count: { id: true },
    });

    // Get auto vs manual moderation ratio
    const [autoModerated, manualModerated] = await Promise.all([
      prisma.moderationAction.count({
        where: { createdAt: { gte: startDate }, isAutomated: true },
      }),
      prisma.moderationAction.count({
        where: { createdAt: { gte: startDate }, isAutomated: false },
      }),
    ]);

    // Get average resolution time
    const resolvedReports = await prisma.contentReport.findMany({
      where: {
        createdAt: { gte: startDate },
        reviewedAt: { not: null },
      },
      select: { createdAt: true, reviewedAt: true },
    });

    const avgResolutionTime = resolvedReports.length > 0
      ? resolvedReports.reduce((acc, r) => {
          return acc + ((r.reviewedAt?.getTime() || 0) - r.createdAt.getTime());
        }, 0) / resolvedReports.length / (1000 * 60 * 60) // Convert to hours
      : 0;

    // Get top moderators
    const topModerators = await prisma.moderationAction.groupBy({
      by: ['performedBy'],
      where: {
        createdAt: { gte: startDate },
        isAutomated: false,
      },
      _count: { id: true },
      orderBy: { _count: { id: 'desc' } },
      take: 10,
    });

    res.json({
      period,
      reportsByCategory: reportsByCategory.map(r => ({
        category: r.category,
        count: r._count.id,
      })),
      reportsByStatus: reportsByStatus.map(r => ({
        status: r.status,
        count: r._count.id,
      })),
      actionsByType: actionsByType.map(a => ({
        type: a.actionType,
        count: a._count.id,
      })),
      automationRatio: {
        automated: autoModerated,
        manual: manualModerated,
        ratio: autoModerated / (autoModerated + manualModerated || 1),
      },
      avgResolutionTimeHours: Math.round(avgResolutionTime * 10) / 10,
      topModerators: topModerators.map(m => ({
        moderatorId: m.performedBy,
        actionsCount: m._count.id,
      })),
    });
  } catch (error) {
    console.error('Error fetching moderation analytics:', error);
    res.status(500).json({ error: 'Failed to fetch analytics' });
  }
});

// ============================================================================
// REPORT MANAGEMENT
// ============================================================================

/**
 * GET /api/admin/moderation/reports
 * Get pending reports for review
 */
router.get('/reports', requireAdmin, requirePermission('canViewReports'), async (req: Request, res: Response) => {
  try {
    const { status, priority, category, page, limit } = req.query;

    const result = await getPendingReports({
      status: status as string,
      priority: priority as string,
      category: category as string,
      page: page ? parseInt(page as string) : undefined,
      limit: limit ? parseInt(limit as string) : undefined,
    });

    res.json(result);
  } catch (error) {
    console.error('Error fetching reports:', error);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

/**
 * GET /api/admin/moderation/reports/:reportId
 * Get detailed report information
 */
router.get('/reports/:reportId', requireAdmin, requirePermission('canViewReports'), async (req: Request, res: Response) => {
  try {
    const { reportId } = req.params;

    const report = await prisma.contentReport.findUnique({
      where: { id: reportId },
    });

    if (!report) {
      return res.status(404).json({ error: 'Report not found' });
    }

    // Get reporter info
    const reporter = await prisma.user.findUnique({
      where: { id: report.reporterId },
      select: { id: true, displayName: true, email: true },
    });

    // Get reported content details
    let reportedContent: any = null;
    let reportedUser: any = null;

    if (report.reportedUserId) {
      reportedUser = await prisma.user.findUnique({
        where: { id: report.reportedUserId },
        select: {
          id: true,
          displayName: true,
          email: true,
          profileImageUrl: true,
          createdAt: true,
        },
      });
    }

    if (report.reportedPulseId) {
      reportedContent = await prisma.pulse.findUnique({
        where: { id: report.reportedPulseId },
        include: {
          author: { select: { id: true, displayName: true } },
        },
      });
    }

    if (report.reportedMessageId) {
      reportedContent = await prisma.message.findUnique({
        where: { id: report.reportedMessageId },
        include: {
          sender: { select: { id: true, displayName: true } },
        },
      });
    }

    if (report.reportedHighlightId) {
      reportedContent = await prisma.highlight.findUnique({
        where: { id: report.reportedHighlightId },
        include: {
          user: { select: { id: true, displayName: true } },
        },
      });
    }

    // Get previous reports for the same content/user
    const previousReports = await prisma.contentReport.count({
      where: {
        OR: [
          { reportedUserId: report.reportedUserId },
          { reportedPulseId: report.reportedPulseId },
          { reportedMessageId: report.reportedMessageId },
          { reportedHighlightId: report.reportedHighlightId },
        ].filter(cond => Object.values(cond)[0] !== null),
        id: { not: reportId },
      },
    });

    // Get moderation status if user report
    let moderationStatus: Awaited<ReturnType<typeof prisma.userModerationStatus.findUnique>> = null;
    const targetUserId = report.reportedUserId || 
                         (reportedContent as any)?.authorId || 
                         (reportedContent as any)?.senderId ||
                         (reportedContent as any)?.userId;
    
    if (targetUserId) {
      moderationStatus = await prisma.userModerationStatus.findUnique({
        where: { userId: targetUserId },
      });
    }

    res.json({
      report,
      reporter,
      reportedUser,
      reportedContent,
      previousReports,
      moderationStatus,
    });
  } catch (error) {
    console.error('Error fetching report details:', error);
    res.status(500).json({ error: 'Failed to fetch report details' });
  }
});

/**
 * POST /api/admin/moderation/reports/:reportId/resolve
 * Resolve a report with action
 */
router.post('/reports/:reportId/resolve', requireAdmin, requirePermission('canResolveReports'), async (req: Request, res: Response) => {
  try {
    const { reportId } = req.params;
    const { resolution, actionTaken, resolutionNote, actions } = req.body;
    const auth = (req as any).adminAuth;

    // Validate
    if (!resolution) {
      return res.status(400).json({ error: 'Resolution is required' });
    }

    const report = await prisma.contentReport.findUnique({
      where: { id: reportId },
    });

    if (!report) {
      return res.status(404).json({ error: 'Report not found' });
    }

    // Execute requested actions
    if (actions) {
      const targetUserId = report.reportedUserId;

      if (actions.warn && targetUserId && auth.admin.canWarnUsers) {
        await warnUser(targetUserId, actions.warnReason || report.category, auth.user.id, reportId);
      }

      if (actions.mute && targetUserId && auth.admin.canMuteUsers) {
        await muteUser(targetUserId, actions.muteReason || report.category, actions.muteDuration, auth.user.id, reportId);
      }

      if (actions.suspend && targetUserId && auth.admin.canSuspendUsers) {
        await suspendUser(targetUserId, actions.suspendReason || report.category, actions.suspendDuration, auth.user.id, reportId);
      }

      if (actions.ban && targetUserId && auth.admin.canBanUsers) {
        await banUser(targetUserId, actions.banReason || report.category, auth.user.id, reportId);
      }

      if (actions.hideContent && auth.admin.canRemoveContent) {
        if (report.reportedPulseId) {
          await hideContent('pulse', report.reportedPulseId, auth.user.id, report.category);
        }
        if (report.reportedMessageId) {
          await hideContent('message', report.reportedMessageId, auth.user.id, report.category);
        }
        if (report.reportedHighlightId) {
          await hideContent('highlight', report.reportedHighlightId, auth.user.id, report.category);
        }
      }

      if (actions.removeContent && auth.admin.canRemoveContent) {
        if (report.reportedPulseId) {
          await removeContent('pulse', report.reportedPulseId, auth.user.id, report.category);
        }
        if (report.reportedMessageId) {
          await removeContent('message', report.reportedMessageId, auth.user.id, report.category);
        }
        if (report.reportedHighlightId) {
          await removeContent('highlight', report.reportedHighlightId, auth.user.id, report.category);
        }
      }

      // Reduce trust score for violations
      if (actions.reduceTrust && targetUserId) {
        await reduceTrustScore(targetUserId, actions.trustReduction || 0.1);
      }
    }

    // Resolve the report
    await resolveReport(reportId, resolution, actionTaken, resolutionNote, auth.user.id);

    // Update admin stats
    await prisma.adminUser.update({
      where: { id: auth.admin.id },
      data: {
        reportsReviewed: { increment: 1 },
        actionsPerformed: { increment: actions ? Object.keys(actions).length : 0 },
        lastActiveAt: new Date(),
      },
    });

    // Log action
    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'RESOLVE_REPORT',
      targetType: 'REPORT',
      targetId: reportId,
      details: { resolution, actionTaken, actions },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'Report resolved successfully' });
  } catch (error) {
    console.error('Error resolving report:', error);
    res.status(500).json({ error: 'Failed to resolve report' });
  }
});

/**
 * POST /api/admin/moderation/reports/:reportId/dismiss
 * Dismiss a report without action
 */
router.post('/reports/:reportId/dismiss', requireAdmin, requirePermission('canResolveReports'), async (req: Request, res: Response) => {
  try {
    const { reportId } = req.params;
    const { resolutionNote } = req.body;
    const auth = (req as any).adminAuth;

    await dismissReport(reportId, resolutionNote, auth.user.id);

    // Update admin stats
    await prisma.adminUser.update({
      where: { id: auth.admin.id },
      data: {
        reportsReviewed: { increment: 1 },
        lastActiveAt: new Date(),
      },
    });

    // Log action
    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'DISMISS_REPORT',
      targetType: 'REPORT',
      targetId: reportId,
      details: { resolutionNote },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'Report dismissed' });
  } catch (error) {
    console.error('Error dismissing report:', error);
    res.status(500).json({ error: 'Failed to dismiss report' });
  }
});

// ============================================================================
// USER MODERATION
// ============================================================================

/**
 * GET /api/admin/moderation/users/:userId
 * Get user moderation profile
 */
router.get('/users/:userId', requireAdmin, requirePermission('canViewReports'), async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const [user, moderationStatus, recentReports, recentActions] = await Promise.all([
      prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          displayName: true,
          email: true,
          profileImageUrl: true,
          createdAt: true,
        },
      }),
      prisma.userModerationStatus.findUnique({
        where: { userId },
      }),
      prisma.contentReport.findMany({
        where: { reportedUserId: userId },
        orderBy: { createdAt: 'desc' },
        take: 10,
      }),
      prisma.moderationAction.findMany({
        where: { targetUserId: userId },
        orderBy: { createdAt: 'desc' },
        take: 10,
      }),
    ]);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({
      user,
      moderationStatus,
      recentReports,
      recentActions,
    });
  } catch (error) {
    console.error('Error fetching user moderation profile:', error);
    res.status(500).json({ error: 'Failed to fetch user profile' });
  }
});

/**
 * POST /api/admin/moderation/users/:userId/warn
 * Warn a user
 */
router.post('/users/:userId/warn', requireAdmin, requirePermission('canWarnUsers'), async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { reason } = req.body;
    const auth = (req as any).adminAuth;

    if (!reason) {
      return res.status(400).json({ error: 'Reason is required' });
    }

    await warnUser(userId, reason, auth.user.id);

    res.json({ success: true, message: 'User warned successfully' });
  } catch (error) {
    console.error('Error warning user:', error);
    res.status(500).json({ error: 'Failed to warn user' });
  }
});

/**
 * POST /api/admin/moderation/users/:userId/mute
 * Mute a user
 */
router.post('/users/:userId/mute', requireAdmin, requirePermission('canMuteUsers'), async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { reason, durationHours } = req.body;
    const auth = (req as any).adminAuth;

    if (!reason) {
      return res.status(400).json({ error: 'Reason is required' });
    }

    await muteUser(userId, reason, durationHours, auth.user.id);

    res.json({ success: true, message: 'User muted successfully' });
  } catch (error) {
    console.error('Error muting user:', error);
    res.status(500).json({ error: 'Failed to mute user' });
  }
});

/**
 * POST /api/admin/moderation/users/:userId/suspend
 * Suspend a user
 */
router.post('/users/:userId/suspend', requireAdmin, requirePermission('canSuspendUsers'), async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { reason, durationHours } = req.body;
    const auth = (req as any).adminAuth;

    if (!reason || !durationHours) {
      return res.status(400).json({ error: 'Reason and duration are required' });
    }

    await suspendUser(userId, reason, durationHours, auth.user.id);

    res.json({ success: true, message: 'User suspended successfully' });
  } catch (error) {
    console.error('Error suspending user:', error);
    res.status(500).json({ error: 'Failed to suspend user' });
  }
});

/**
 * POST /api/admin/moderation/users/:userId/ban
 * Ban a user
 */
router.post('/users/:userId/ban', requireAdmin, requirePermission('canBanUsers'), async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { reason } = req.body;
    const auth = (req as any).adminAuth;

    if (!reason) {
      return res.status(400).json({ error: 'Reason is required' });
    }

    await banUser(userId, reason, auth.user.id);

    res.json({ success: true, message: 'User banned successfully' });
  } catch (error) {
    console.error('Error banning user:', error);
    res.status(500).json({ error: 'Failed to ban user' });
  }
});

/**
 * POST /api/admin/moderation/users/:userId/unban
 * Unban a user
 */
router.post('/users/:userId/unban', requireAdmin, requirePermission('canBanUsers'), async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { reason } = req.body;
    const auth = (req as any).adminAuth;

    await prisma.userModerationStatus.update({
      where: { userId },
      data: {
        isBanned: false,
        bannedAt: null,
        banReason: null,
        isSuspended: false,
        suspendedUntil: null,
        suspendReason: null,
        isMuted: false,
        mutedUntil: null,
        muteReason: null,
      },
    });

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'UNBAN_USER',
      targetType: 'USER',
      targetId: userId,
      details: { reason },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'User unbanned successfully' });
  } catch (error) {
    console.error('Error unbanning user:', error);
    res.status(500).json({ error: 'Failed to unban user' });
  }
});

// ============================================================================
// CONTENT MODERATION
// ============================================================================

/**
 * POST /api/admin/moderation/content/hide
 * Hide content
 */
router.post('/content/hide', requireAdmin, requirePermission('canRemoveContent'), async (req: Request, res: Response) => {
  try {
    const { type, id, reason } = req.body;
    const auth = (req as any).adminAuth;

    if (!type || !id) {
      return res.status(400).json({ error: 'Type and ID are required' });
    }

    await hideContent(type, id, auth.user.id, reason);

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'HIDE_CONTENT',
      targetType: type.toUpperCase(),
      targetId: id,
      details: { reason },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'Content hidden successfully' });
  } catch (error) {
    console.error('Error hiding content:', error);
    res.status(500).json({ error: 'Failed to hide content' });
  }
});

/**
 * POST /api/admin/moderation/content/remove
 * Remove content
 */
router.post('/content/remove', requireAdmin, requirePermission('canRemoveContent'), async (req: Request, res: Response) => {
  try {
    const { type, id, reason } = req.body;
    const auth = (req as any).adminAuth;

    if (!type || !id) {
      return res.status(400).json({ error: 'Type and ID are required' });
    }

    await removeContent(type, id, auth.user.id, reason);

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'REMOVE_CONTENT',
      targetType: type.toUpperCase(),
      targetId: id,
      details: { reason },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'Content removed successfully' });
  } catch (error) {
    console.error('Error removing content:', error);
    res.status(500).json({ error: 'Failed to remove content' });
  }
});

/**
 * POST /api/admin/moderation/content/restore
 * Restore hidden/removed content
 */
router.post('/content/restore', requireAdmin, requirePermission('canRemoveContent'), async (req: Request, res: Response) => {
  try {
    const { type, id, reason } = req.body;
    const auth = (req as any).adminAuth;

    if (!type || !id) {
      return res.status(400).json({ error: 'Type and ID are required' });
    }

    await restoreContent(type, id);

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'RESTORE_CONTENT',
      targetType: type.toUpperCase(),
      targetId: id,
      details: { reason },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'Content restored successfully' });
  } catch (error) {
    console.error('Error restoring content:', error);
    res.status(500).json({ error: 'Failed to restore content' });
  }
});

// ============================================================================
// APPEAL MANAGEMENT
// ============================================================================

/**
 * GET /api/admin/moderation/appeals
 * Get pending appeals
 */
router.get('/appeals', requireAdmin, requirePermission('canResolveReports'), async (req: Request, res: Response) => {
  try {
    const appeals = await prisma.moderationAction.findMany({
      where: { appealStatus: 'PENDING' },
      orderBy: { appealedAt: 'asc' },
    });

    res.json(appeals);
  } catch (error) {
    console.error('Error fetching appeals:', error);
    res.status(500).json({ error: 'Failed to fetch appeals' });
  }
});

/**
 * POST /api/admin/moderation/appeals/:actionId/review
 * Review an appeal
 */
router.post('/appeals/:actionId/review', requireAdmin, requirePermission('canResolveReports'), async (req: Request, res: Response) => {
  try {
    const { actionId } = req.params;
    const { decision, note } = req.body; // decision: 'GRANTED' or 'DENIED'
    const auth = (req as any).adminAuth;

    if (!decision || !['GRANTED', 'DENIED'].includes(decision)) {
      return res.status(400).json({ error: 'Valid decision is required' });
    }

    const action = await prisma.moderationAction.findUnique({
      where: { id: actionId },
    });

    if (!action) {
      return res.status(404).json({ error: 'Action not found' });
    }

    await prisma.moderationAction.update({
      where: { id: actionId },
      data: {
        appealStatus: decision,
        appealReviewedBy: auth.user.id,
        appealReviewedAt: new Date(),
      },
    });

    // If appeal granted, reverse the action
    if (decision === 'GRANTED' && action.targetUserId) {
      await prisma.userModerationStatus.update({
        where: { userId: action.targetUserId },
        data: {
          isMuted: action.actionType === 'USER_MUTED' ? false : undefined,
          isSuspended: action.actionType === 'USER_SUSPENDED' ? false : undefined,
          isBanned: action.actionType === 'USER_BANNED' ? false : undefined,
        },
      });

      // Restore content if applicable
      if (action.targetPulseId) {
        await restoreContent('pulse', action.targetPulseId);
      }
      if (action.targetMessageId) {
        await restoreContent('message', action.targetMessageId);
      }
      if (action.targetHighlightId) {
        await restoreContent('highlight', action.targetHighlightId);
      }
    }

    await logModerationAction({
      adminUserId: auth.user.id,
      action: `APPEAL_${decision}`,
      targetType: 'MODERATION_ACTION',
      targetId: actionId,
      details: { note, originalAction: action.actionType },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: `Appeal ${decision.toLowerCase()}` });
  } catch (error) {
    console.error('Error reviewing appeal:', error);
    res.status(500).json({ error: 'Failed to review appeal' });
  }
});

// ============================================================================
// AUDIT LOG
// ============================================================================

/**
 * GET /api/admin/moderation/audit-log
 * Get moderation audit log
 */
router.get('/audit-log', requireAdmin, requirePermission('canViewAnalytics'), async (req: Request, res: Response) => {
  try {
    const { page = '1', limit = '50', adminUserId, action, targetType } = req.query;

    const where: any = {};
    if (adminUserId) where.adminUserId = adminUserId;
    if (action) where.action = action;
    if (targetType) where.targetType = targetType;

    const [logs, total] = await Promise.all([
      prisma.moderationAuditLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (parseInt(page as string) - 1) * parseInt(limit as string),
        take: parseInt(limit as string),
      }),
      prisma.moderationAuditLog.count({ where }),
    ]);

    res.json({ logs, total, page: parseInt(page as string), limit: parseInt(limit as string) });
  } catch (error) {
    console.error('Error fetching audit log:', error);
    res.status(500).json({ error: 'Failed to fetch audit log' });
  }
});

// ============================================================================
// ADMIN MANAGEMENT
// ============================================================================

/**
 * GET /api/admin/moderation/admins
 * Get list of admin users
 */
router.get('/admins', requireAdmin, requirePermission('canManageAdmins'), async (req: Request, res: Response) => {
  try {
    const admins = await prisma.adminUser.findMany();

    // Get user details
    const userIds = admins.map(a => a.userId);
    const users = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, displayName: true, email: true, profileImageUrl: true },
    });

    const userMap = new Map(users.map(u => [u.id, u]));

    res.json(admins.map(a => ({
      ...a,
      user: userMap.get(a.userId),
    })));
  } catch (error) {
    console.error('Error fetching admins:', error);
    res.status(500).json({ error: 'Failed to fetch admins' });
  }
});

/**
 * POST /api/admin/moderation/admins
 * Create a new admin user
 */
router.post('/admins', requireAdmin, requirePermission('canManageAdmins'), async (req: Request, res: Response) => {
  try {
    const { userId, role, permissions } = req.body;
    const auth = (req as any).adminAuth;

    if (!userId || !role) {
      return res.status(400).json({ error: 'User ID and role are required' });
    }

    // Verify user exists
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if already admin
    const existingAdmin = await prisma.adminUser.findUnique({ where: { userId } });
    if (existingAdmin) {
      return res.status(400).json({ error: 'User is already an admin' });
    }

    const admin = await prisma.adminUser.create({
      data: {
        userId,
        role,
        ...permissions,
      },
    });

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'CREATE_ADMIN',
      targetType: 'ADMIN',
      targetId: admin.id,
      details: { userId, role },
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.status(201).json(admin);
  } catch (error) {
    console.error('Error creating admin:', error);
    res.status(500).json({ error: 'Failed to create admin' });
  }
});

/**
 * PATCH /api/admin/moderation/admins/:adminId
 * Update admin permissions
 */
router.patch('/admins/:adminId', requireAdmin, requirePermission('canManageAdmins'), async (req: Request, res: Response) => {
  try {
    const { adminId } = req.params;
    const updates = req.body;
    const auth = (req as any).adminAuth;

    const admin = await prisma.adminUser.update({
      where: { id: adminId },
      data: updates,
    });

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'UPDATE_ADMIN',
      targetType: 'ADMIN',
      targetId: adminId,
      details: updates,
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json(admin);
  } catch (error) {
    console.error('Error updating admin:', error);
    res.status(500).json({ error: 'Failed to update admin' });
  }
});

/**
 * DELETE /api/admin/moderation/admins/:adminId
 * Remove admin privileges
 */
router.delete('/admins/:adminId', requireAdmin, requirePermission('canManageAdmins'), async (req: Request, res: Response) => {
  try {
    const { adminId } = req.params;
    const auth = (req as any).adminAuth;

    await prisma.adminUser.delete({
      where: { id: adminId },
    });

    await logModerationAction({
      adminUserId: auth.user.id,
      action: 'DELETE_ADMIN',
      targetType: 'ADMIN',
      targetId: adminId,
      ipAddress: req.ip,
      userAgent: req.get('user-agent'),
    });

    res.json({ success: true, message: 'Admin removed' });
  } catch (error) {
    console.error('Error removing admin:', error);
    res.status(500).json({ error: 'Failed to remove admin' });
  }
});

export default router;
