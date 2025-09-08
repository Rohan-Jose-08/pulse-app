import express from 'express';
import { PrismaClient } from '@prisma/client';
import admin from '../firebase';

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
		const decoded = await admin.auth().verifyIdToken(idToken);
		const { uid } = decoded;
		const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
		if (!user) return res.status(401).json({ error: 'User not found' });
		req.user = user;
		next();
	} catch (err) {
		console.error(err);
		res.status(401).json({ error: 'Unauthorized' });
	}
};

// Create or get a one-to-one conversation between current user and target user
router.post('/conversations/with/:otherUserId', authenticateUser, async (req, res) => {
	try {
		const otherUserId = req.params.otherUserId;
		const me = req.user.id as string;

		if (otherUserId === me) return res.status(400).json({ error: 'Cannot create conversation with yourself' });

		// Find existing conversation with both participants (naive check)
		let convo = await prisma.conversation.findFirst({
			where: {
				AND: [
					{ participants: { some: { id: me } } },
					{ participants: { some: { id: otherUserId } } },
				],
			},
			include: { participants: true },
		});

		if (!convo) {
			convo = await prisma.conversation.create({
				data: {
					participants: {
						connect: [{ id: me }, { id: otherUserId }],
					},
				},
				include: { participants: true },
			});
		}

		res.json(convo);
	} catch (e) {
		console.error('create/get conversation error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

// List my conversations
router.get('/conversations', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const convos = await (prisma as any).conversation.findMany({
			where: { participants: { some: { id: me } } },
			orderBy: { updatedAt: 'desc' },
			include: {
				participants: { select: { id: true, displayName: true, profileImageUrl: true } },
				pulse: { select: { id: true, title: true, imageUrl: true } },
			},
		});
		res.json(convos.map((c: any) => ({
			id: c.id,
			participants: c.participants,
			updatedAt: c.updatedAt,
			createdAt: c.createdAt,
			lastMessageText: c.lastMessageText,
			lastSenderId: c.lastSenderId,
			isGroup: c.isGroup,
			name: c.name || c.pulse?.title || null,
			avatarUrl: c.avatarUrl || c.pulse?.imageUrl || null,
			pulseId: c.pulseId,
		}))); 
	} catch (e) {
		console.error('list conversations error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

// Get paginated messages for a conversation
router.get('/conversations/:id/messages', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const { id } = req.params;
		const { cursor, limit = '30' } = req.query as { cursor?: string; limit?: string };
		const take = Math.max(1, Math.min(parseInt(limit as string, 10) || 30, 100));

		const convo = await prisma.conversation.findUnique({
			where: { id },
			include: { participants: true },
		});
		if (!convo) return res.status(404).json({ error: 'Conversation not found' });
		const isParticipant = convo.participants.some((p) => p.id === me);
		if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });

		const messages = await prisma.message.findMany({
			where: { conversationId: id },
			orderBy: { createdAt: 'desc' },
			take,
			cursor: cursor ? { id: cursor } : undefined,
			skip: cursor ? 1 : 0,
		});

		// Fetch reactions for these messages
		const ids = messages.map(m => m.id);
		let reactions: { messageId: string; emoji: string; userId: string }[] = [];
		if (ids.length) {
			// @ts-ignore - messageReaction available after prisma generate
			reactions = await (prisma as any).messageReaction.findMany({
				where: { messageId: { in: ids } },
				select: { messageId: true, emoji: true, userId: true },
			});
		}
		const reactionMap: Record<string, Record<string, string[]>> = {};
		reactions.forEach(r => {
			if (!reactionMap[r.messageId]) reactionMap[r.messageId] = {};
			if (!reactionMap[r.messageId][r.emoji]) reactionMap[r.messageId][r.emoji] = [];
			reactionMap[r.messageId][r.emoji].push(r.userId);
		});

		res.json({
			messages: messages.reverse().map(m => ({
				...m,
				reactions: reactionMap[m.id] || {},
			})),
			nextCursor: messages.length === take ? messages[messages.length - 1].id : null,
		});
	} catch (e) {
		console.error('list messages error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

// Invite members to a conversation (creates pending invitations + notification)
router.post('/conversations/:id/invitations', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const { id } = req.params;
		const { userIds } = req.body as { userIds?: string[] };
		if (!Array.isArray(userIds) || userIds.length === 0) {
			return res.status(400).json({ error: 'userIds required' });
		}
		const convo = await prisma.conversation.findUnique({ where: { id }, include: { participants: true } });
		if (!convo) return res.status(404).json({ error: 'Conversation not found' });
		const isParticipant = convo.participants.some(p => p.id === me);
		if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });
		const created: any[] = [];
		for (const targetId of userIds) {
			if (!targetId || targetId === me) continue;
			const alreadyParticipant = convo.participants.some(p => p.id === targetId);
			if (alreadyParticipant) continue;
			try {
				const invite = await prisma.conversationInvitation.upsert({
					where: { conversationId_inviteeId: { conversationId: id, inviteeId: targetId } },
					update: { status: 'PENDING' },
					create: { conversationId: id, inviterId: me, inviteeId: targetId },
				});
				// Create notification for invitee
				await prisma.notification.create({
					data: {
						userId: targetId,
						type: 'INVITE',
						title: 'Pulse Chat Invitation',
						message: 'You have been invited to join a chat',
						data: { conversationId: id, inviterId: me, invitationId: invite.id },
					},
				});
				created.push(invite);
			} catch (e) {
				console.error('Invite create error', e);
			}
		}
		res.json({ ok: true, created });
	} catch (e) {
		console.error('invite members error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

// List my pending invitations
router.get('/invitations', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const list = await prisma.conversationInvitation.findMany({
			where: { inviteeId: me, status: 'PENDING' },
			include: { conversation: true },
			orderBy: { createdAt: 'desc' },
		});
		res.json(list);
	} catch (e) {
		console.error('list invites error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

// Accept or decline an invitation
router.post('/invitations/:invitationId/respond', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const { invitationId } = req.params;
		const { action } = req.body as { action?: string };
		const normalized = (action || '').toUpperCase();
		if (!['ACCEPT', 'DECLINE'].includes(normalized)) {
			return res.status(400).json({ error: 'Invalid action' });
		}
		const invitation = await prisma.conversationInvitation.findUnique({ where: { id: invitationId } });
		if (!invitation || invitation.inviteeId !== me) {
			return res.status(404).json({ error: 'Invitation not found' });
		}
		if (invitation.status !== 'PENDING') {
			return res.status(400).json({ error: 'Invitation already responded' });
		}
		if (normalized === 'ACCEPT') {
			// Add user to conversation participants
			await prisma.conversation.update({
				where: { id: invitation.conversationId },
				data: { participants: { connect: { id: me } } },
			});
			await prisma.conversationInvitation.update({
				where: { id: invitationId },
				data: { status: 'ACCEPTED', respondedAt: new Date() },
			});

			// Find and update the related notification for this invitee so it reflects the join
			try {
				const notif = await prisma.notification.findFirst({
					where: {
						userId: me,
						type: 'INVITE',
					},
					orderBy: { createdAt: 'desc' },
					take: 50,
				});
				// If we found a recent INVITE, check the payload to match invitationId
				let targetNotif = notif;
				if (!targetNotif) {
					// no-op
				} else {
					// If payload doesn't match, try to scan a few more
					const recent = await prisma.notification.findMany({
						where: { userId: me, type: 'INVITE' },
						orderBy: { createdAt: 'desc' },
						take: 20,
					});
					targetNotif = recent.find((n: any) => {
						const data: any = n.data || {};
						return String(data.invitationId || '') === invitationId;
					}) as any || targetNotif;
				}
				if (targetNotif) {
					await prisma.notification.update({
						where: { id: targetNotif.id },
						data: {
							type: 'INFO',
							title: 'Joined group chat',
							message: 'You have joined this group chat',
							isRead: true,
							data: {
								conversationId: invitation.conversationId,
								invitationId,
								status: 'ACCEPTED',
							} as any,
						},
					});
				}
			} catch (notifyErr) {
				console.error('Failed to update invite notification on accept:', notifyErr);
			}
			return res.json({ ok: true, status: 'ACCEPTED' });
		} else {
			await prisma.conversationInvitation.update({
				where: { id: invitationId },
				data: { status: 'DECLINED', respondedAt: new Date() },
			});
			// Find and remove the related notification so it disappears from the feed
			try {
				const recent = await prisma.notification.findMany({
					where: { userId: me, type: 'INVITE' },
					orderBy: { createdAt: 'desc' },
					take: 20,
				});
				const target = recent.find((n: any) => {
					const data: any = n.data || {};
					return String(data.invitationId || '') === invitationId;
				});
				if (target) {
					await prisma.notification.delete({ where: { id: target.id } });
				}
			} catch (notifyErr) {
				console.error('Failed to delete invite notification on decline:', notifyErr);
			}
			return res.json({ ok: true, status: 'DECLINED' });
		}
	} catch (e) {
		console.error('respond invite error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

export default router;


