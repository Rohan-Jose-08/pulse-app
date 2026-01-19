/**
 * Moderation Routes
 * 
 * Handles content reporting, user blocking/muting, and moderation actions.
 */

import { Router, Request, Response } from 'express';
import { PrismaClient } from '@prisma/client';
import { getAuth } from 'firebase-admin/auth';
import {
  createReport,
  REPORT_CATEGORIES,
  REPORT_SUBCATEGORIES,
  hideContent,
  removeContent,
  restoreContent,
  isContentVisible,
  getUserModerationStatus,
  logModerationAction,
} from '../services/moderation';

const router = Router();
const prisma = new PrismaClient();

// Helper to get authenticated user
async function getAuthenticatedUser(req: Request): Promise<{ id: string; firebaseUid: string } | null> {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(token);
    const user = await prisma.user.findUnique({
      where: { firebaseUid: decodedToken.uid },
      select: { id: true, firebaseUid: true },
    });
    return user;
  } catch {
    return null;
  }
}

// ============================================================================
// CONTENT REPORTING
// ============================================================================

/**
 * GET /api/moderation/report-categories
 * Get available report categories and subcategories
 */
router.get('/report-categories', (req: Request, res: Response) => {
  res.json({
    categories: Object.keys(REPORT_CATEGORIES),
    subcategories: REPORT_SUBCATEGORIES,
  });
});

/**
 * POST /api/moderation/reports
 * Create a new content report
 */
router.post('/reports', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    console.log('Create report request body:', JSON.stringify(req.body, null, 2));
    console.log('Authenticated user:', user.id);

    const {
      reportedUserId,
      reportedPulseId,
      reportedMessageId,
      reportedHighlightId,
      reportedPostId,
      category,
      subcategory,
      description,
      evidence,
    } = req.body;

    // Validate category
    if (!category || !Object.keys(REPORT_CATEGORIES).includes(category)) {
      return res.status(400).json({ error: 'Invalid report category' });
    }

    // Can't report yourself
    if (reportedUserId === user.id) {
      return res.status(400).json({ error: 'Cannot report yourself' });
    }

    // Check if user has already reported this content recently
    const recentReport = await prisma.contentReport.findFirst({
      where: {
        reporterId: user.id,
        reportedUserId,
        reportedPulseId,
        reportedMessageId,
        reportedHighlightId,
        reportedPostId,
        createdAt: {
          gte: new Date(Date.now() - 24 * 60 * 60 * 1000), // Last 24 hours
        },
      },
    });

    if (recentReport) {
      return res.status(429).json({ error: 'You have already reported this content recently' });
    }

    const report = await createReport({
      reporterId: user.id,
      reportedUserId,
      reportedPulseId,
      reportedMessageId,
      reportedHighlightId,
      reportedPostId,
      category,
      subcategory,
      description,
      evidence,
    });

    res.status(201).json({
      success: true,
      reportId: report.id,
      message: 'Report submitted successfully. Our team will review it shortly.',
    });
  } catch (error: any) {
    console.error('Error creating report:', error?.message || error);
    console.error('Error stack:', error?.stack);
    console.error('Request body:', req.body);
    res.status(500).json({ error: 'Failed to submit report', details: error?.message });
  }
});

/**
 * GET /api/moderation/my-reports
 * Get reports submitted by the current user
 */
router.get('/my-reports', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const reports = await prisma.contentReport.findMany({
      where: { reporterId: user.id },
      select: {
        id: true,
        category: true,
        subcategory: true,
        status: true,
        createdAt: true,
        resolution: true,
        reviewedAt: true,
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });

    res.json(reports);
  } catch (error) {
    console.error('Error fetching user reports:', error);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

// ============================================================================
// USER BLOCKING
// ============================================================================

/**
 * POST /api/moderation/block
 * Block a user
 */
router.post('/block', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { userId: blockedUserId, reason } = req.body;

    if (!blockedUserId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    if (blockedUserId === user.id) {
      return res.status(400).json({ error: 'Cannot block yourself' });
    }

    // Check if target user exists
    const targetUser = await prisma.user.findUnique({
      where: { id: blockedUserId },
    });

    if (!targetUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Create or update block
    await prisma.blockedUser.upsert({
      where: {
        blockingUserId_blockedUserId: {
          blockingUserId: user.id,
          blockedUserId,
        },
      },
      create: {
        blockingUserId: user.id,
        blockedUserId,
        reason,
      },
      update: {
        reason,
        createdAt: new Date(),
      },
    });

    // Remove any follow relationship
    await prisma.follow.deleteMany({
      where: {
        OR: [
          { followerId: user.id, followingId: blockedUserId },
          { followerId: blockedUserId, followingId: user.id },
        ],
      },
    });

    // Log action
    await logModerationAction({
      action: 'USER_BLOCK',
      targetType: 'USER',
      targetId: blockedUserId,
      details: { blockedBy: user.id, reason },
    });

    res.json({ success: true, message: 'User blocked successfully' });
  } catch (error) {
    console.error('Error blocking user:', error);
    res.status(500).json({ error: 'Failed to block user' });
  }
});

/**
 * DELETE /api/moderation/block/:userId
 * Unblock a user
 */
router.delete('/block/:userId', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { userId: blockedUserId } = req.params;

    await prisma.blockedUser.deleteMany({
      where: {
        blockingUserId: user.id,
        blockedUserId,
      },
    });

    res.json({ success: true, message: 'User unblocked successfully' });
  } catch (error) {
    console.error('Error unblocking user:', error);
    res.status(500).json({ error: 'Failed to unblock user' });
  }
});

/**
 * GET /api/moderation/blocked-users
 * Get list of blocked users
 */
router.get('/blocked-users', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const blockedUsers = await prisma.blockedUser.findMany({
      where: { blockingUserId: user.id },
      include: {
        blockedUser: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json(blockedUsers.map(b => ({
      id: b.blockedUser.id,
      displayName: b.blockedUser.displayName,
      profileImageUrl: b.blockedUser.profileImageUrl,
      blockedAt: b.createdAt,
      reason: b.reason,
    })));
  } catch (error) {
    console.error('Error fetching blocked users:', error);
    res.status(500).json({ error: 'Failed to fetch blocked users' });
  }
});

/**
 * GET /api/moderation/is-blocked/:userId
 * Check if a user is blocked
 */
router.get('/is-blocked/:userId', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { userId: targetUserId } = req.params;

    const [blockedByMe, blockedMe] = await Promise.all([
      prisma.blockedUser.findUnique({
        where: {
          blockingUserId_blockedUserId: {
            blockingUserId: user.id,
            blockedUserId: targetUserId,
          },
        },
      }),
      prisma.blockedUser.findUnique({
        where: {
          blockingUserId_blockedUserId: {
            blockingUserId: targetUserId,
            blockedUserId: user.id,
          },
        },
      }),
    ]);

    res.json({
      blockedByMe: !!blockedByMe,
      blockedMe: !!blockedMe,
      isBlocked: !!blockedByMe || !!blockedMe,
    });
  } catch (error) {
    console.error('Error checking block status:', error);
    res.status(500).json({ error: 'Failed to check block status' });
  }
});

// ============================================================================
// USER MUTING
// ============================================================================

/**
 * POST /api/moderation/mute
 * Mute a user (hide their content without blocking)
 */
router.post('/mute', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { userId: mutedUserId, reason, muteMessages = true, mutePulses = true, mutePosts = true } = req.body;

    if (!mutedUserId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    if (mutedUserId === user.id) {
      return res.status(400).json({ error: 'Cannot mute yourself' });
    }

    await prisma.mutedUser.upsert({
      where: {
        mutingUserId_mutedUserId: {
          mutingUserId: user.id,
          mutedUserId,
        },
      },
      create: {
        mutingUserId: user.id,
        mutedUserId,
        reason,
        muteMessages,
        mutePulses,
        mutePosts,
      },
      update: {
        reason,
        muteMessages,
        mutePulses,
        mutePosts,
      },
    });

    res.json({ success: true, message: 'User muted successfully' });
  } catch (error) {
    console.error('Error muting user:', error);
    res.status(500).json({ error: 'Failed to mute user' });
  }
});

/**
 * DELETE /api/moderation/mute/:userId
 * Unmute a user
 */
router.delete('/mute/:userId', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { userId: mutedUserId } = req.params;

    await prisma.mutedUser.deleteMany({
      where: {
        mutingUserId: user.id,
        mutedUserId,
      },
    });

    res.json({ success: true, message: 'User unmuted successfully' });
  } catch (error) {
    console.error('Error unmuting user:', error);
    res.status(500).json({ error: 'Failed to unmute user' });
  }
});

/**
 * GET /api/moderation/muted-users
 * Get list of muted users
 */
router.get('/muted-users', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const mutedUsers = await prisma.mutedUser.findMany({
      where: { mutingUserId: user.id },
      select: {
        mutedUserId: true,
        reason: true,
        muteMessages: true,
        mutePulses: true,
        mutePosts: true,
        createdAt: true,
      },
    });

    // Get user details
    const userIds = mutedUsers.map(m => m.mutedUserId);
    const users = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: {
        id: true,
        displayName: true,
        profileImageUrl: true,
      },
    });

    const userMap = new Map(users.map(u => [u.id, u]));

    res.json(mutedUsers.map(m => ({
      ...userMap.get(m.mutedUserId),
      mutedAt: m.createdAt,
      reason: m.reason,
      muteMessages: m.muteMessages,
      mutePulses: m.mutePulses,
      mutePosts: m.mutePosts,
    })));
  } catch (error) {
    console.error('Error fetching muted users:', error);
    res.status(500).json({ error: 'Failed to fetch muted users' });
  }
});

/**
 * GET /api/moderation/muted-user-ids
 * Get IDs of muted users (for filtering)
 */
router.get('/muted-user-ids', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const mutedUsers = await prisma.mutedUser.findMany({
      where: { mutingUserId: user.id },
      select: {
        mutedUserId: true,
        muteMessages: true,
        mutePulses: true,
        mutePosts: true,
      },
    });

    res.json({
      mutedForMessages: mutedUsers.filter(m => m.muteMessages).map(m => m.mutedUserId),
      mutedForPulses: mutedUsers.filter(m => m.mutePulses).map(m => m.mutedUserId),
      mutedForPosts: mutedUsers.filter(m => m.mutePosts).map(m => m.mutedUserId),
    });
  } catch (error) {
    console.error('Error fetching muted user IDs:', error);
    res.status(500).json({ error: 'Failed to fetch muted user IDs' });
  }
});

// ============================================================================
// MODERATION STATUS
// ============================================================================

/**
 * GET /api/moderation/my-status
 * Get current user's moderation status
 */
router.get('/my-status', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const status = await getUserModerationStatus(user.id);

    // Don't expose internal scores to user
    res.json({
      isMuted: status.isMuted,
      mutedUntil: status.mutedUntil,
      muteReason: status.muteReason,
      isSuspended: status.isSuspended,
      suspendedUntil: status.suspendedUntil,
      suspendReason: status.suspendReason,
      isBanned: status.isBanned,
      banReason: status.banReason,
      canCreatePulses: status.canCreatePulses,
      canSendMessages: status.canSendMessages,
      canPostHighlights: status.canPostHighlights,
      warningCount: status.warningCount,
    });
  } catch (error) {
    console.error('Error fetching moderation status:', error);
    res.status(500).json({ error: 'Failed to fetch moderation status' });
  }
});

/**
 * GET /api/moderation/my-actions
 * Get moderation actions taken against current user
 */
router.get('/my-actions', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const actions = await prisma.moderationAction.findMany({
      where: { targetUserId: user.id },
      select: {
        id: true,
        actionType: true,
        reason: true,
        category: true,
        duration: true,
        expiresAt: true,
        appealStatus: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });

    res.json(actions);
  } catch (error) {
    console.error('Error fetching moderation actions:', error);
    res.status(500).json({ error: 'Failed to fetch moderation actions' });
  }
});

/**
 * POST /api/moderation/appeal/:actionId
 * Appeal a moderation action
 */
router.post('/appeal/:actionId', async (req: Request, res: Response) => {
  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { actionId } = req.params;
    const { appealNote } = req.body;

    if (!appealNote) {
      return res.status(400).json({ error: 'Appeal note is required' });
    }

    const action = await prisma.moderationAction.findUnique({
      where: { id: actionId },
    });

    if (!action || action.targetUserId !== user.id) {
      return res.status(404).json({ error: 'Action not found' });
    }

    if (action.appealStatus && action.appealStatus !== 'NONE') {
      return res.status(400).json({ error: 'An appeal has already been submitted' });
    }

    // Check appeal cooldown
    const status = await getUserModerationStatus(user.id);
    if (status.appealCooldown && status.appealCooldown > new Date()) {
      return res.status(429).json({ 
        error: 'Please wait before submitting another appeal',
        cooldownUntil: status.appealCooldown,
      });
    }

    await prisma.moderationAction.update({
      where: { id: actionId },
      data: {
        appealStatus: 'PENDING',
        appealNote,
        appealedAt: new Date(),
      },
    });

    // Set cooldown (7 days)
    await prisma.userModerationStatus.update({
      where: { userId: user.id },
      data: {
        lastAppealAt: new Date(),
        appealCooldown: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    res.json({ success: true, message: 'Appeal submitted successfully' });
  } catch (error) {
    console.error('Error submitting appeal:', error);
    res.status(500).json({ error: 'Failed to submit appeal' });
  }
});

// ============================================================================
// CONTENT VISIBILITY CHECK
// ============================================================================

/**
 * GET /api/moderation/content-visible
 * Check if content is visible (not moderated)
 */
router.get('/content-visible', async (req: Request, res: Response) => {
  try {
    const { type, id } = req.query as { type?: string; id?: string };

    if (!type || !id) {
      return res.status(400).json({ error: 'Type and ID are required' });
    }

    if (!['pulse', 'message', 'highlight', 'post'].includes(type)) {
      return res.status(400).json({ error: 'Invalid content type' });
    }

    const visible = await isContentVisible(type as any, id);
    res.json({ visible });
  } catch (error) {
    console.error('Error checking content visibility:', error);
    res.status(500).json({ error: 'Failed to check content visibility' });
  }
});

export default router;
