import express from 'express';
import { PrismaClient } from '@prisma/client';

const router = express.Router();
const prisma = new PrismaClient();

// Extend Express Request type to include user
declare global {
  namespace Express {
    interface Request {
      user?: any;
    }
  }
}

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

// POST /api/pulses/:pulseId/invite - Invite users to a pulse
router.post('/:pulseId/invite', authenticateUser, async (req, res) => {
  try {
    const { pulseId } = req.params;
    const inviterId = req.user.id;
    const { userIds } = req.body as { userIds: string[] };

    if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
      return res.status(400).json({ error: 'userIds array is required' });
    }

    // Check if pulse exists and if user is a participant or author
    const pulse = await prisma.pulse.findUnique({
      where: { id: pulseId },
      include: {
        participants: { select: { id: true } },
        author: { select: { id: true, displayName: true } },
        conversations: { select: { id: true } }
      }
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check if inviter is a participant or author
    const isParticipant = pulse.participants.some(p => p.id === inviterId) || pulse.authorId === inviterId;
    if (!isParticipant) {
      return res.status(403).json({ error: 'Only pulse participants can invite others' });
    }

    const invitations = [];
    const errors = [];

    for (const inviteeId of userIds) {
      if (inviteeId === inviterId) {
        errors.push({ userId: inviteeId, error: 'Cannot invite yourself' });
        continue;
      }

      // Check if invitee exists
      const invitee = await prisma.user.findUnique({
        where: { id: inviteeId },
        select: { id: true, displayName: true }
      });

      if (!invitee) {
        errors.push({ userId: inviteeId, error: 'User not found' });
        continue;
      }

      // Check if already a participant or author
      const isAlreadyMember = pulse.participants.some(p => p.id === inviteeId) || pulse.authorId === inviteeId;
      if (isAlreadyMember) {
        errors.push({ userId: inviteeId, error: 'User is already a pulse member' });
        continue;
      }

      try {
        // Create or update pulse invitation (using ConversationInvitation model)
        // First, ensure the pulse conversation exists
        let conversation = pulse.conversations[0];
        if (!conversation) {
          // Create conversation if it doesn't exist
          conversation = await (prisma as any).conversation.create({
            data: {
              pulse: { connect: { id: pulseId } },
              isGroup: true,
              name: pulse.title,
              avatarUrl: pulse.imageUrl,
              participants: {
                connect: [
                  { id: pulse.authorId },
                  ...pulse.participants.map(p => ({ id: p.id }))
                ]
              }
            }
          });
        }

        // Check if invitation already exists
        const existingInvitation = await prisma.conversationInvitation.findFirst({
          where: {
            conversationId: conversation.id,
            inviteeId,
            status: 'PENDING'
          }
        });

        const invitation = existingInvitation
          ? await prisma.conversationInvitation.update({
              where: { id: existingInvitation.id },
              data: {
                status: 'PENDING',
                invitationType: 'PULSE_CHAT',
                respondedAt: null
              },
              include: {
                inviter: {
                  select: {
                    id: true,
                    displayName: true,
                    profileImageUrl: true
                  }
                },
                invitee: {
                  select: {
                    id: true,
                    displayName: true,
                    profileImageUrl: true
                  }
                }
              }
            })
          : await prisma.conversationInvitation.create({
              data: {
                conversationId: conversation.id,
                inviterId,
                inviteeId,
                status: 'PENDING',
                invitationType: 'PULSE_CHAT'
              },
              include: {
                inviter: {
                  select: {
                    id: true,
                    displayName: true,
                    profileImageUrl: true
                  }
                },
            invitee: {
              select: {
                id: true,
                displayName: true,
                profileImageUrl: true
              }
            }
          }
        });

        // Create notification for invitee
        await prisma.notification.create({
          data: {
            userId: inviteeId,
            type: 'PULSE_INVITE',
            title: 'Pulse Invitation',
            message: `${pulse.author.displayName} invited you to join "${pulse.title}"`,
            data: {
              pulseId,
              conversationId: conversation.id,
              invitationId: invitation.id,
              inviterId,
              pulseTitle: pulse.title,
              pulseImageUrl: pulse.imageUrl
            }
          }
        });

        invitations.push({
          ...invitation,
          pulseId,
          pulseTitle: pulse.title
        });
      } catch (error) {
        console.error(`Error creating invitation for ${inviteeId}:`, error);
        errors.push({ userId: inviteeId, error: 'Failed to create invitation' });
      }
    }

    res.json({
      success: true,
      invitations,
      errors: errors.length > 0 ? errors : undefined
    });
  } catch (error) {
    console.error('Error inviting users to pulse:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/pulses/invitations - List pending pulse invitations for current user
router.get('/invitations', authenticateUser, async (req, res) => {
  try {
    const userId = req.user.id;

    const invitations = await prisma.conversationInvitation.findMany({
      where: {
        inviteeId: userId,
        status: 'PENDING',
        conversation: {
          pulseId: { not: null }
        }
      },
      include: {
        inviter: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true
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
            }
          }
        }
      },
      orderBy: { createdAt: 'desc' }
    });

    res.json(invitations.map(inv => ({
      id: inv.id,
      inviter: inv.inviter,
      pulse: inv.conversation?.pulse || null,
      conversationId: inv.conversationId,
      createdAt: inv.createdAt
    })));
  } catch (error) {
    console.error('Error fetching pulse invitations:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/pulses/invitations/:invitationId/respond - Accept or decline invitation
router.post('/invitations/:invitationId/respond', authenticateUser, async (req, res) => {
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
                author: { select: { id: true } }
              }
            }
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

    if (!invitation.conversation) {
      return res.status(404).json({ error: 'Associated conversation not found' });
    }

    const pulse = invitation.conversation.pulse;
    if (!pulse) {
      return res.status(404).json({ error: 'Associated pulse not found' });
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
      // Check if user is already a participant
      const isAlreadyParticipant = pulse.participants.some(p => p.id === userId) || pulse.authorId === userId;

      if (!isAlreadyParticipant) {
        // Add user as participant to the pulse
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

        // Add user to the conversation
        await (prisma as any).conversation.update({
          where: { id: invitation.conversationId },
          data: {
            participants: {
              connect: { id: userId }
            }
          }
        });

        // Create notification for inviter
        await prisma.notification.create({
          data: {
            userId: invitation.inviterId,
            type: 'PULSE_INVITE_ACCEPTED',
            title: 'Invitation Accepted',
            message: `${req.user.displayName} accepted your invitation to join "${pulse.title}"`,
            data: {
              pulseId: pulse.id,
              acceptedBy: userId
            }
          }
        });
      }

      res.json({
        success: true,
        message: 'Invitation accepted',
        pulse: {
          id: pulse.id,
          title: pulse.title,
          imageUrl: pulse.imageUrl
        }
      });
    } else {
      res.json({
        success: true,
        message: 'Invitation declined'
      });
    }
  } catch (error) {
    console.error('Error responding to invitation:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
