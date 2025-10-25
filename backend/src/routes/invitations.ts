import express from 'express';
import { PrismaClient } from '@prisma/client';

const router = express.Router();
const prisma = new PrismaClient();

// Middleware to authenticate users
const authenticateUser = async (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).send('Missing or invalid token');
  }

  const idToken = authHeader.split(' ')[1];

  try {
    const admin = require('../firebase').default;
    const decoded = await admin.auth().verifyIdToken(idToken);
    const { uid } = decoded;
    
    const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }
    
    req.user = user;
    next();
  } catch (err) {
    console.error(err);
    res.status(401).json({ error: 'Unauthorized' });
  }
};

// GET /api/invitations - List all pending invitations for current user (unified)
router.get('/', authenticateUser, async (req, res) => {
  try {
    const userId = req.user.id;
    const { type } = req.query as { type?: string };

    // Build where clause - optionally filter by invitation type
    const whereClause: any = {
      inviteeId: userId,
      status: 'PENDING'
    };

    if (type) {
      whereClause.invitationType = type.toUpperCase();
    }

    const invitations = await prisma.conversationInvitation.findMany({
      where: whereClause,
      include: {
        inviter: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
            bio: true,
            followersCount: true,
            followingCount: true
          }
        },
        conversation: {
          include: {
            pulse: {
              select: {
                id: true,
                title: true,
                description: true,
                imageUrl: true,
                eventTime: true,
                location: true,
                activeFrom: true,
                activeUntil: true,
                author: {
                  select: {
                    id: true,
                    displayName: true,
                    profileImageUrl: true
                  }
                }
              }
            },
            participants: {
              select: {
                id: true,
                displayName: true,
                profileImageUrl: true
              },
              take: 5 // Show first 5 participants for group chats
            }
          }
        }
      },
      orderBy: { createdAt: 'desc' }
    });

    // Format response to include type-specific data
    const formattedInvitations = invitations.map(inv => {
      const base = {
        id: inv.id,
        type: inv.invitationType,
        status: inv.status,
        inviter: inv.inviter,
        conversationId: inv.conversationId,
        createdAt: inv.createdAt,
        respondedAt: inv.respondedAt
      };

      // Add type-specific data
      if (inv.invitationType === 'FOLLOW_REQUEST') {
        return {
          ...base,
          inviter: inv.inviter // Follow requests only need inviter info
        };
      } else if (inv.invitationType === 'PULSE_CHAT' && inv.conversation?.pulse) {
        return {
          ...base,
          pulse: inv.conversation.pulse,
          conversation: {
            id: inv.conversation.id,
            name: inv.conversation.name,
            isGroup: inv.conversation.isGroup,
            avatarUrl: inv.conversation.avatarUrl
          }
        };
      } else if (inv.conversation) {
        return {
          ...base,
          conversation: {
            id: inv.conversation.id,
            name: inv.conversation.name,
            isGroup: inv.conversation.isGroup,
            avatarUrl: inv.conversation.avatarUrl,
            participants: inv.conversation.participants
          }
        };
      } else {
        return base;
      }
    });

    res.json(formattedInvitations);
  } catch (error) {
    console.error('Error fetching invitations:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/invitations/:invitationId/respond - Accept or decline any invitation (unified)
router.post('/:invitationId/respond', authenticateUser, async (req, res) => {
  try {
    const { invitationId } = req.params;
    const userId = req.user.id;
    const { accept } = req.body as { accept: boolean };

    if (typeof accept !== 'boolean') {
      return res.status(400).json({ error: 'accept field is required (boolean)' });
    }

    // Find the invitation
    const invitation = await prisma.conversationInvitation.findUnique({
      where: { id: invitationId },
      include: {
        conversation: {
          include: {
            pulse: {
              include: {
                participants: { select: { id: true } },
                author: { select: { id: true, displayName: true } }
              }
            },
            participants: {
              select: { id: true }
            }
          }
        },
        inviter: {
          select: {
            id: true,
            displayName: true
          }
        }
      }
    });

    if (!invitation) {
      return res.status(404).json({ error: 'Invitation not found' });
    }

    if (invitation.inviteeId !== userId) {
      return res.status(403).json({ error: 'Not your invitation' });
    }

    if (invitation.status !== 'PENDING') {
      return res.status(400).json({ error: 'Invitation already responded to' });
    }

    // Update invitation status
    await prisma.conversationInvitation.update({
      where: { id: invitationId },
      data: {
        status: accept ? 'ACCEPTED' : 'DECLINED',
        respondedAt: new Date()
      }
    });

    if (accept) {
      const isFollowRequest = invitation.invitationType === 'FOLLOW_REQUEST';
      const isPulseChat = invitation.invitationType === 'PULSE_CHAT';
      const pulse = invitation.conversation?.pulse;

      if (isFollowRequest) {
        // Handle follow request acceptance
        const existingFollow = await prisma.follow.findUnique({
          where: {
            followerId_followingId: {
              followerId: invitation.inviterId,
              followingId: userId
            }
          }
        });

        if (!existingFollow) {
          // Create follow relationship
          await prisma.follow.create({
            data: {
              followerId: invitation.inviterId,
              followingId: userId
            }
          });

          // Update follower counts
          await prisma.user.update({
            where: { id: userId },
            data: { followersCount: { increment: 1 } }
          });

          await prisma.user.update({
            where: { id: invitation.inviterId },
            data: { followingCount: { increment: 1 } }
          });
        }

        // Create notification for requester
        await prisma.notification.create({
          data: {
            userId: invitation.inviterId,
            type: 'FOLLOW_REQUEST_ACCEPTED',
            title: 'Follow Request Accepted',
            message: `${req.user.displayName} accepted your follow request`,
            data: {
              acceptedBy: userId
            }
          }
        });

        res.json({
          success: true,
          message: 'Follow request accepted',
          invitationType: invitation.invitationType
        });
      } else if (invitation.conversation) {
        // Check if user is already a participant in the conversation
        const isAlreadyParticipant = invitation.conversation.participants.some(p => p.id === userId);

        if (!isAlreadyParticipant) {
          // Add user to the conversation
          await (prisma as any).conversation.update({
            where: { id: invitation.conversationId },
            data: {
              participants: {
                connect: { id: userId }
              }
            }
          });

          // If it's a pulse chat, also add to pulse participants
          if (isPulseChat && pulse) {
            const isAlreadyPulseParticipant = pulse.participants.some(p => p.id === userId) || pulse.authorId === userId;

            if (!isAlreadyPulseParticipant) {
              await prisma.pulse.update({
                where: { id: pulse.id },
                data: {
                  participants: {
                    connect: { id: userId }
                  },
                  currentParticipants: {
                    increment: 1
                  }
                }
              });
            }
          }

          // Create notification for inviter
          const notificationMessage = isPulseChat && pulse
            ? `${req.user.displayName} accepted your invitation to join "${pulse.title}"`
            : `${req.user.displayName} accepted your chat invitation`;

          await prisma.notification.create({
            data: {
              userId: invitation.inviterId,
              type: isPulseChat ? 'PULSE_INVITE_ACCEPTED' : 'INVITE_ACCEPTED',
              title: 'Invitation Accepted',
              message: notificationMessage,
              data: {
                conversationId: invitation.conversationId,
                acceptedBy: userId,
                ...(isPulseChat && pulse ? { pulseId: pulse.id } : {})
              }
            }
          });
        }

        const responseData: any = {
          success: true,
          message: 'Invitation accepted',
          conversationId: invitation.conversationId,
          invitationType: invitation.invitationType
        };

        if (isPulseChat && pulse) {
          responseData.pulse = {
            id: pulse.id,
            title: pulse.title,
            imageUrl: pulse.imageUrl
          };
        }

        res.json(responseData);
      } else {
        res.status(400).json({ error: 'Invalid invitation data' });
      }
    } else {
      res.json({
        success: true,
        message: 'Invitation declined',
        invitationType: invitation.invitationType
      });
    }
  } catch (error) {
    console.error('Error responding to invitation:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/invitations/count - Get count of pending invitations by type
router.get('/count', authenticateUser, async (req, res) => {
  try {
    const userId = req.user.id;

    const counts = await prisma.conversationInvitation.groupBy({
      by: ['invitationType'],
      where: {
        inviteeId: userId,
        status: 'PENDING'
      },
      _count: true
    });

    const result = counts.reduce((acc, item) => {
      acc[item.invitationType.toLowerCase()] = item._count;
      return acc;
    }, {} as Record<string, number>);

    // Add total count
    result.total = Object.values(result).reduce((sum, count) => sum + count, 0);

    res.json(result);
  } catch (error) {
    console.error('Error fetching invitation counts:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
