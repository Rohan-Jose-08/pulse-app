import { Router, Request, Response } from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticateUser } from '../middleware/auth';

const router = Router();
const prisma = new PrismaClient();

// Role hierarchy: OWNER > ADMIN > MODERATOR > MEMBER
const ROLE_HIERARCHY = {
  OWNER: 4,
  ADMIN: 3,
  MODERATOR: 2,
  MEMBER: 1,
};

type PulseRole = keyof typeof ROLE_HIERARCHY;

// Helper: Check if user has permission based on role
function hasHigherOrEqualRole(userRole: string, requiredRole: string): boolean {
  const userLevel = ROLE_HIERARCHY[userRole as PulseRole] || 0;
  const requiredLevel = ROLE_HIERARCHY[requiredRole as PulseRole] || 0;
  return userLevel >= requiredLevel;
}

// Helper: Get member's effective permissions
function getEffectivePermissions(member: any, pulse: any) {
  const role = member.role as PulseRole;
  const isOwner = role === 'OWNER';
  const isAdmin = role === 'ADMIN' || isOwner;
  const isModerator = role === 'MODERATOR' || isAdmin;

  return {
    canInvite: member.canInvite ?? (pulse.allowGuestInvites || isAdmin),
    canRemove: member.canRemove ?? isAdmin,
    canEdit: member.canEdit ?? isAdmin,
    canManageChat: member.canManageChat ?? isModerator,
    canChangeRoles: isAdmin,
    canDeletePulse: isOwner,
    canArchivePulse: isOwner,
    canTransferOwnership: isOwner,
  };
}

// Apply authentication to all routes
router.use(authenticateUser);

/**
 * GET /api/pulses/:id/members
 * Get all members of a pulse with their roles
 */
router.get('/:id/members', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = (req as any).user.id;

    // Get the pulse
    const pulse = await prisma.pulse.findUnique({
      where: { id },
      include: {
        author: {
          select: { id: true, displayName: true, email: true, profileImageUrl: true },
        },
        participants: {
          select: { id: true, displayName: true, email: true, profileImageUrl: true },
        },
      },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check if user is author or participant
    const isAuthor = pulse.authorId === userId;
    const isParticipant = pulse.participants.some(p => p.id === userId);
    
    if (!isAuthor && !isParticipant) {
      return res.status(403).json({ error: 'Not authorized to view pulse members' });
    }

    // Get members from PulseMember table (if exists) or fall back to participants
    let members: any[] = [];
    
    try {
      const pulseMembers = await (prisma as any).pulseMember.findMany({
        where: { pulseId: id },
        orderBy: [
          { role: 'asc' },
          { joinedAt: 'asc' },
        ],
      });

      if (pulseMembers.length > 0) {
        // Fetch user details for each member
        const userIds = pulseMembers.map((m: any) => m.userId);
        const users = await prisma.user.findMany({
          where: { id: { in: userIds } },
          select: { id: true, displayName: true, email: true, profileImageUrl: true },
        });

        const userMap = new Map(users.map(u => [u.id, u]));

        members = pulseMembers.map((m: any) => {
          const user = userMap.get(m.userId);
          return {
            ...m,
            user,
            permissions: getEffectivePermissions(m, pulse),
          };
        });
      }
    } catch (e) {
      // PulseMember table might not exist yet, fall back to legacy
    }

    // If no PulseMember records, create virtual member list from participants
    if (members.length === 0) {
      // Add author as OWNER
      members.push({
        id: `virtual-${pulse.authorId}`,
        pulseId: id,
        userId: pulse.authorId,
        role: 'OWNER',
        joinedAt: pulse.createdAt,
        user: pulse.author,
        permissions: {
          canInvite: true,
          canRemove: true,
          canEdit: true,
          canManageChat: true,
          canChangeRoles: true,
          canDeletePulse: true,
          canArchivePulse: true,
          canTransferOwnership: true,
        },
      });

      // Add participants as MEMBER
      pulse.participants.forEach(p => {
        members.push({
          id: `virtual-${p.id}`,
          pulseId: id,
          userId: p.id,
          role: 'MEMBER',
          joinedAt: pulse.createdAt,
          user: p,
          permissions: {
            canInvite: (pulse as any).allowGuestInvites ?? true,
            canRemove: false,
            canEdit: false,
            canManageChat: false,
            canChangeRoles: false,
            canDeletePulse: false,
            canArchivePulse: false,
            canTransferOwnership: false,
          },
        });
      });
    }

    // Get current user's role
    const currentUserMember = members.find(m => m.userId === userId);
    const currentUserRole = currentUserMember?.role || 'MEMBER';
    const currentUserPermissions = currentUserMember?.permissions || {};

    res.json({
      pulseId: id,
      totalMembers: members.length,
      currentUser: {
        userId,
        role: currentUserRole,
        permissions: currentUserPermissions,
      },
      members,
    });
  } catch (error) {
    console.error('Error fetching pulse members:', error);
    res.status(500).json({ error: 'Failed to fetch pulse members' });
  }
});

/**
 * POST /api/pulses/:id/members/:userId/role
 * Update a member's role (requires ADMIN or higher)
 */
router.post('/:id/members/:userId/role', async (req: Request, res: Response) => {
  try {
    const { id, userId: targetUserId } = req.params;
    const { role } = req.body;
    const actingUserId = (req as any).user.id;

    if (!role || !['ADMIN', 'MODERATOR', 'MEMBER'].includes(role)) {
      return res.status(400).json({ error: 'Invalid role. Must be ADMIN, MODERATOR, or MEMBER' });
    }

    // Get the pulse
    const pulse = await prisma.pulse.findUnique({
      where: { id },
      include: { participants: true },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {
      // Table might not exist
    }

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    // Need ADMIN or higher to change roles
    if (!hasHigherOrEqualRole(actingRole, 'ADMIN')) {
      return res.status(403).json({ error: 'Only admins can change member roles' });
    }

    // Cannot change owner's role
    if (targetUserId === pulse.authorId) {
      return res.status(403).json({ error: 'Cannot change the owner\'s role' });
    }

    // Cannot set role higher than your own (except owner)
    if (!isOwner && ROLE_HIERARCHY[role as PulseRole] >= ROLE_HIERARCHY[actingRole as PulseRole]) {
      return res.status(403).json({ error: 'Cannot set a role equal to or higher than your own' });
    }

    // Ensure target is a participant
    const isParticipant = pulse.participants.some(p => p.id === targetUserId) || pulse.authorId === targetUserId;
    if (!isParticipant) {
      return res.status(404).json({ error: 'User is not a member of this pulse' });
    }

    // Update or create PulseMember record
    const member = await (prisma as any).pulseMember.upsert({
      where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      update: { role },
      create: {
        pulseId: id,
        userId: targetUserId,
        role,
        joinedAt: new Date(),
      },
    });

    // Create notification for the user
    await prisma.notification.create({
      data: {
        userId: targetUserId,
        type: 'PULSE_ROLE_CHANGED',
        title: 'Role Updated',
        message: `Your role in "${pulse.title}" has been changed to ${role}`,
        data: { pulseId: id, newRole: role },
      },
    });

    res.json({
      success: true,
      message: `User role updated to ${role}`,
      member: {
        ...member,
        permissions: getEffectivePermissions(member, pulse),
      },
    });
  } catch (error) {
    console.error('Error updating member role:', error);
    res.status(500).json({ error: 'Failed to update member role' });
  }
});

/**
 * POST /api/pulses/:id/members/:userId/remove
 * Remove a member from the pulse (kick)
 */
router.post('/:id/members/:userId/remove', async (req: Request, res: Response) => {
  try {
    const { id, userId: targetUserId } = req.params;
    const { reason } = req.body;
    const actingUserId = (req as any).user.id;

    // Get the pulse
    const pulse = await prisma.pulse.findUnique({
      where: { id },
      include: { participants: true },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {
      // Table might not exist
    }

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    // Need ADMIN or higher to remove members
    if (!hasHigherOrEqualRole(actingRole, 'ADMIN')) {
      return res.status(403).json({ error: 'Only admins can remove members' });
    }

    // Cannot remove the owner
    if (targetUserId === pulse.authorId) {
      return res.status(403).json({ error: 'Cannot remove the pulse owner' });
    }

    // Check target user's role - cannot remove someone of equal or higher rank
    let targetMember: any = null;
    try {
      targetMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      });
    } catch (e) {
      // Table might not exist
    }

    const targetRole = targetMember?.role || 'MEMBER';
    if (!isOwner && ROLE_HIERARCHY[targetRole as PulseRole] >= ROLE_HIERARCHY[actingRole as PulseRole]) {
      return res.status(403).json({ error: 'Cannot remove a member of equal or higher rank' });
    }

    // Remove from participants
    await prisma.pulse.update({
      where: { id },
      data: {
        participants: { disconnect: { id: targetUserId } },
        currentParticipants: { decrement: 1 },
      },
    });

    // Remove from PulseMember if exists
    try {
      await (prisma as any).pulseMember.delete({
        where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      });
    } catch (e) {
      // May not exist
    }

    // Remove from pulse conversation
    try {
      const convo = await (prisma as any).conversation.findFirst({
        where: { pulseId: id },
      });
      if (convo) {
        await (prisma as any).conversation.update({
          where: { id: convo.id },
          data: { participants: { disconnect: { id: targetUserId } } },
        });
      }
    } catch (e) {
      console.warn('Failed to remove from conversation:', e);
    }

    // Create notification
    await prisma.notification.create({
      data: {
        userId: targetUserId,
        type: 'PULSE_REMOVED',
        title: 'Removed from Pulse',
        message: reason 
          ? `You have been removed from "${pulse.title}". Reason: ${reason}`
          : `You have been removed from "${pulse.title}"`,
        data: { pulseId: id, reason },
      },
    });

    res.json({
      success: true,
      message: 'Member removed successfully',
    });
  } catch (error) {
    console.error('Error removing member:', error);
    res.status(500).json({ error: 'Failed to remove member' });
  }
});

/**
 * POST /api/pulses/:id/members/:userId/ban
 * Ban a member from the pulse
 */
router.post('/:id/members/:userId/ban', async (req: Request, res: Response) => {
  try {
    const { id, userId: targetUserId } = req.params;
    const { reason } = req.body;
    const actingUserId = (req as any).user.id;

    // Get the pulse
    const pulse = await prisma.pulse.findUnique({
      where: { id },
      include: { participants: true },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {
      // Table might not exist
    }

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    // Need ADMIN or higher to ban
    if (!hasHigherOrEqualRole(actingRole, 'ADMIN')) {
      return res.status(403).json({ error: 'Only admins can ban members' });
    }

    // Cannot ban the owner
    if (targetUserId === pulse.authorId) {
      return res.status(403).json({ error: 'Cannot ban the pulse owner' });
    }

    // First, remove from participants
    await prisma.pulse.update({
      where: { id },
      data: {
        participants: { disconnect: { id: targetUserId } },
        currentParticipants: { decrement: 1 },
      },
    });

    // Update or create PulseMember with banned status
    await (prisma as any).pulseMember.upsert({
      where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      update: {
        isBanned: true,
        bannedAt: new Date(),
        bannedReason: reason || null,
      },
      create: {
        pulseId: id,
        userId: targetUserId,
        role: 'MEMBER',
        isBanned: true,
        bannedAt: new Date(),
        bannedReason: reason || null,
      },
    });

    // Remove from conversation
    try {
      const convo = await (prisma as any).conversation.findFirst({
        where: { pulseId: id },
      });
      if (convo) {
        await (prisma as any).conversation.update({
          where: { id: convo.id },
          data: { participants: { disconnect: { id: targetUserId } } },
        });
      }
    } catch (e) {
      console.warn('Failed to remove from conversation:', e);
    }

    // Create notification
    await prisma.notification.create({
      data: {
        userId: targetUserId,
        type: 'PULSE_BANNED',
        title: 'Banned from Pulse',
        message: reason 
          ? `You have been banned from "${pulse.title}". Reason: ${reason}`
          : `You have been banned from "${pulse.title}"`,
        data: { pulseId: id, reason },
      },
    });

    res.json({
      success: true,
      message: 'Member banned successfully',
    });
  } catch (error) {
    console.error('Error banning member:', error);
    res.status(500).json({ error: 'Failed to ban member' });
  }
});

/**
 * POST /api/pulses/:id/members/:userId/unban
 * Unban a member from the pulse
 */
router.post('/:id/members/:userId/unban', async (req: Request, res: Response) => {
  try {
    const { id, userId: targetUserId } = req.params;
    const actingUserId = (req as any).user.id;

    // Get the pulse
    const pulse = await prisma.pulse.findUnique({
      where: { id },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {
      // Table might not exist
    }

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    // Need ADMIN or higher to unban
    if (!hasHigherOrEqualRole(actingRole, 'ADMIN')) {
      return res.status(403).json({ error: 'Only admins can unban members' });
    }

    // Update PulseMember
    await (prisma as any).pulseMember.update({
      where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      data: {
        isBanned: false,
        bannedAt: null,
        bannedReason: null,
      },
    });

    // Create notification
    await prisma.notification.create({
      data: {
        userId: targetUserId,
        type: 'PULSE_UNBANNED',
        title: 'Unbanned from Pulse',
        message: `You have been unbanned from "${pulse.title}" and can rejoin`,
        data: { pulseId: id },
      },
    });

    res.json({
      success: true,
      message: 'Member unbanned successfully',
    });
  } catch (error) {
    console.error('Error unbanning member:', error);
    res.status(500).json({ error: 'Failed to unban member' });
  }
});

/**
 * POST /api/pulses/:id/members/:userId/mute
 * Mute a member in pulse chat
 */
router.post('/:id/members/:userId/mute', async (req: Request, res: Response) => {
  try {
    const { id, userId: targetUserId } = req.params;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {}

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    // Need MODERATOR or higher to mute
    if (!hasHigherOrEqualRole(actingRole, 'MODERATOR')) {
      return res.status(403).json({ error: 'Only moderators can mute members' });
    }

    // Cannot mute the owner
    if (targetUserId === pulse.authorId) {
      return res.status(403).json({ error: 'Cannot mute the pulse owner' });
    }

    await (prisma as any).pulseMember.upsert({
      where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      update: { isMuted: true },
      create: {
        pulseId: id,
        userId: targetUserId,
        role: 'MEMBER',
        isMuted: true,
      },
    });

    res.json({ success: true, message: 'Member muted' });
  } catch (error) {
    console.error('Error muting member:', error);
    res.status(500).json({ error: 'Failed to mute member' });
  }
});

/**
 * POST /api/pulses/:id/members/:userId/unmute
 * Unmute a member in pulse chat
 */
router.post('/:id/members/:userId/unmute', async (req: Request, res: Response) => {
  try {
    const { id, userId: targetUserId } = req.params;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {}

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    if (!hasHigherOrEqualRole(actingRole, 'MODERATOR')) {
      return res.status(403).json({ error: 'Only moderators can unmute members' });
    }

    await (prisma as any).pulseMember.update({
      where: { pulseId_userId: { pulseId: id, userId: targetUserId } },
      data: { isMuted: false },
    });

    res.json({ success: true, message: 'Member unmuted' });
  } catch (error) {
    console.error('Error unmuting member:', error);
    res.status(500).json({ error: 'Failed to unmute member' });
  }
});

/**
 * PUT /api/pulses/:id/settings
 * Update pulse settings (requires ADMIN or higher)
 */
router.put('/:id/settings', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { allowGuestInvites, requireApproval } = req.body;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {}

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    if (!hasHigherOrEqualRole(actingRole, 'ADMIN')) {
      return res.status(403).json({ error: 'Only admins can update pulse settings' });
    }

    const updateData: any = {};
    if (allowGuestInvites !== undefined) updateData.allowGuestInvites = allowGuestInvites;
    if (requireApproval !== undefined) updateData.requireApproval = requireApproval;

    const updated = await prisma.pulse.update({
      where: { id },
      data: updateData,
    });

    res.json({
      success: true,
      message: 'Settings updated',
      pulse: updated,
    });
  } catch (error) {
    console.error('Error updating pulse settings:', error);
    res.status(500).json({ error: 'Failed to update settings' });
  }
});

/**
 * POST /api/pulses/:id/archive
 * Archive a pulse (soft delete - owner only)
 */
router.post('/:id/archive', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Only owner can archive
    if (pulse.authorId !== actingUserId) {
      return res.status(403).json({ error: 'Only the owner can archive the pulse' });
    }

    await prisma.pulse.update({
      where: { id },
      data: { isArchived: true } as any,
    });

    res.json({
      success: true,
      message: 'Pulse archived',
    });
  } catch (error) {
    console.error('Error archiving pulse:', error);
    res.status(500).json({ error: 'Failed to archive pulse' });
  }
});

/**
 * POST /api/pulses/:id/unarchive
 * Unarchive a pulse (owner only)
 */
router.post('/:id/unarchive', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    if (pulse.authorId !== actingUserId) {
      return res.status(403).json({ error: 'Only the owner can unarchive the pulse' });
    }

    await prisma.pulse.update({
      where: { id },
      data: { isArchived: false } as any,
    });

    res.json({
      success: true,
      message: 'Pulse unarchived',
    });
  } catch (error) {
    console.error('Error unarchiving pulse:', error);
    res.status(500).json({ error: 'Failed to unarchive pulse' });
  }
});

/**
 * DELETE /api/pulses/:id
 * Permanently delete a pulse (owner only)
 */
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    if (pulse.authorId !== actingUserId) {
      return res.status(403).json({ error: 'Only the owner can delete the pulse' });
    }

    // Delete related records first
    try {
      await (prisma as any).pulseMember.deleteMany({ where: { pulseId: id } });
    } catch (e) {}

    // Delete pulse (cascades to conversations, highlights, etc.)
    await prisma.pulse.delete({ where: { id } });

    res.json({
      success: true,
      message: 'Pulse deleted',
    });
  } catch (error) {
    console.error('Error deleting pulse:', error);
    res.status(500).json({ error: 'Failed to delete pulse' });
  }
});

/**
 * POST /api/pulses/:id/transfer-ownership
 * Transfer pulse ownership to another admin (owner only)
 */
router.post('/:id/transfer-ownership', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { newOwnerId } = req.body;
    const actingUserId = (req as any).user.id;

    if (!newOwnerId) {
      return res.status(400).json({ error: 'New owner ID is required' });
    }

    const pulse = await prisma.pulse.findUnique({
      where: { id },
      include: { participants: true },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    if (pulse.authorId !== actingUserId) {
      return res.status(403).json({ error: 'Only the owner can transfer ownership' });
    }

    // New owner must be a participant or admin
    const isParticipant = pulse.participants.some(p => p.id === newOwnerId);
    if (!isParticipant && newOwnerId !== pulse.authorId) {
      return res.status(400).json({ error: 'New owner must be a pulse member' });
    }

    // Update pulse author
    await prisma.pulse.update({
      where: { id },
      data: { authorId: newOwnerId },
    });

    // Update member roles
    try {
      // Set new owner as OWNER
      await (prisma as any).pulseMember.upsert({
        where: { pulseId_userId: { pulseId: id, userId: newOwnerId } },
        update: { role: 'OWNER' },
        create: { pulseId: id, userId: newOwnerId, role: 'OWNER' },
      });

      // Demote old owner to ADMIN
      await (prisma as any).pulseMember.upsert({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
        update: { role: 'ADMIN' },
        create: { pulseId: id, userId: actingUserId, role: 'ADMIN' },
      });
    } catch (e) {
      console.warn('Failed to update member roles:', e);
    }

    // Notifications
    await prisma.notification.createMany({
      data: [
        {
          userId: newOwnerId,
          type: 'PULSE_OWNERSHIP_RECEIVED',
          title: 'Ownership Transferred',
          message: `You are now the owner of "${pulse.title}"`,
          data: { pulseId: id },
        },
        {
          userId: actingUserId,
          type: 'PULSE_OWNERSHIP_TRANSFERRED',
          title: 'Ownership Transferred',
          message: `You have transferred ownership of "${pulse.title}"`,
          data: { pulseId: id, newOwnerId },
        },
      ],
    });

    res.json({
      success: true,
      message: 'Ownership transferred successfully',
    });
  } catch (error) {
    console.error('Error transferring ownership:', error);
    res.status(500).json({ error: 'Failed to transfer ownership' });
  }
});

/**
 * GET /api/pulses/:id/banned
 * Get list of banned members (admin only)
 */
router.get('/:id/banned', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const actingUserId = (req as any).user.id;

    const pulse = await prisma.pulse.findUnique({ where: { id } });
    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check acting user's role
    const isOwner = pulse.authorId === actingUserId;
    let actingUserMember: any = null;
    try {
      actingUserMember = await (prisma as any).pulseMember.findUnique({
        where: { pulseId_userId: { pulseId: id, userId: actingUserId } },
      });
    } catch (e) {}

    const actingRole = isOwner ? 'OWNER' : (actingUserMember?.role || 'MEMBER');

    if (!hasHigherOrEqualRole(actingRole, 'ADMIN')) {
      return res.status(403).json({ error: 'Only admins can view banned members' });
    }

    let bannedMembers: any[] = [];
    try {
      bannedMembers = await (prisma as any).pulseMember.findMany({
        where: { pulseId: id, isBanned: true },
      });

      // Get user details
      const userIds = bannedMembers.map((m: any) => m.userId);
      const users = await prisma.user.findMany({
        where: { id: { in: userIds } },
        select: { id: true, displayName: true, email: true, profileImageUrl: true },
      });

      const userMap = new Map(users.map(u => [u.id, u]));
      bannedMembers = bannedMembers.map((m: any) => ({
        ...m,
        user: userMap.get(m.userId),
      }));
    } catch (e) {
      // Table might not exist
    }

    res.json({
      pulseId: id,
      bannedMembers,
    });
  } catch (error) {
    console.error('Error fetching banned members:', error);
    res.status(500).json({ error: 'Failed to fetch banned members' });
  }
});

export default router;
