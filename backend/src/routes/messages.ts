import express from 'express';
import { PrismaClient } from '@prisma/client';
import admin from '../firebase';
import { getIo, userSockets } from '../realtime';

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

		// Resolve the provided id to a legacy Conversation id, supporting
		// DirectConversation/PulseConversation ids or even a pulseId.
		let legacy = await (prisma as any).conversation.findUnique({ where: { id }, include: { participants: true } });
		if (!legacy) {
			// Try direct conversation id
			const dconv = await (prisma as any).directConversation.findUnique({ where: { id }, include: { participants: { select: { id: true } } } }).catch(() => null);
			if (dconv) {
				legacy = await (prisma as any).conversation.findUnique({ where: { id }, include: { participants: true } });
				if (!legacy) {
					legacy = await (prisma as any).conversation.create({
						data: {
							id,
							isGroup: false,
							participants: { connect: (dconv.participants as any[]).map((u: any) => ({ id: u.id })) },
							name: dconv.name ?? undefined,
							avatarUrl: dconv.avatarUrl ?? undefined,
						},
						include: { participants: true },
					});
				}
			}
		}
		if (!legacy) {
			// Try pulse conversation id (or pulse id)
			const pconv = await (prisma as any).pulseConversation.findUnique({ where: { id }, include: { participants: { select: { id: true } }, pulse: { select: { id: true, title: true, imageUrl: true } } } }).catch(() => null);
			if (pconv) {
				let c = await (prisma as any).conversation.findUnique({ where: { id }, include: { participants: true } });
				if (!c && pconv.pulse?.id) {
					c = await (prisma as any).conversation.findFirst({ where: { pulseId: pconv.pulse.id }, include: { participants: true } });
				}
				if (!c && pconv.pulse?.id) {
					c = await (prisma as any).conversation.create({
						data: {
							id,
							isGroup: true,
							pulse: { connect: { id: pconv.pulse.id } },
							participants: { connect: (pconv.participants as any[]).map((u: any) => ({ id: u.id })) },
							name: pconv.pulse?.title ?? undefined,
							avatarUrl: pconv.pulse?.imageUrl ?? undefined,
						},
						include: { participants: true },
					});
				}
				legacy = c ?? null;
			} else {
				// Interpret id directly as pulseId
				const pulse = await prisma.pulse.findUnique({ where: { id } });
				if (pulse) {
					const c = await (prisma as any).conversation.findFirst({ where: { pulseId: id }, include: { participants: true } });
					if (c) legacy = c;
				}
			}
		}

		if (!legacy) return res.status(404).json({ error: 'Conversation not found' });

		const isParticipant = legacy.participants.some((p: any) => p.id === me);
		if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });

		const messages = await prisma.message.findMany({
			where: { conversationId: legacy.id },
			orderBy: { createdAt: 'desc' },
			take,
			cursor: cursor ? { id: cursor } : undefined,
			skip: cursor ? 1 : 0,
			include: {
				sender: {
					select: {
						id: true,
						displayName: true,
						profileImageUrl: true,
					}
				},
				repliedTo: {
					select: {
						id: true,
						text: true,
						imageUrl: true,
						videoUrl: true,
						senderId: true,
						sender: {
							select: {
								id: true,
								displayName: true,
							}
						}
					}
				}
			}
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
				senderName: (m as any).sender?.displayName || null,
				senderPhotoUrl: (m as any).sender?.profileImageUrl || null,
				reactions: reactionMap[m.id] || {},
				deliveredTo: m.deliveredTo || [],
				readBy: m.readBy || [],
				repliedTo: (m as any).repliedTo ? {
					id: (m as any).repliedTo.id,
					text: (m as any).repliedTo.text,
					imageUrl: (m as any).repliedTo.imageUrl,
					videoUrl: (m as any).repliedTo.videoUrl,
					senderId: (m as any).repliedTo.senderId,
					senderName: (m as any).repliedTo.sender?.displayName || 'Unknown',
				} : null,
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
				// Check if invitation already exists
				const existingInvite = await prisma.conversationInvitation.findFirst({
					where: {
						conversationId: id,
						inviteeId: targetId,
						status: 'PENDING'
					}
				});

				const invite = existingInvite 
					? await prisma.conversationInvitation.update({
							where: { id: existingInvite.id },
							data: { status: 'PENDING', invitationType: 'GROUP_CHAT' }
						})
					: await prisma.conversationInvitation.create({
							data: { conversationId: id, inviterId: me, inviteeId: targetId, invitationType: 'GROUP_CHAT' }
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

// NOTE: Legacy invitation endpoints moved to /api/invitations (unified)
// The routes below are DEPRECATED and should not be used
// Use /api/invitations instead for all invitation operations

// List my pending invitations (DEPRECATED - use /api/invitations instead)
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

// DEPRECATED: This endpoint conflicts with the unified /api/invitations/:invitationId/respond
// Kept for backward compatibility but redirects to the new unified endpoint
// TODO: Remove this after all clients are updated
/*
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
		if (!invitation.conversationId) {
			return res.status(400).json({ error: 'Invalid invitation: no conversation associated' });
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
*/

export default router;

// Below: additional helper routes for strict separation of conversation types

// List my direct (1:1 or non-pulse) conversations only
router.get('/conversations-direct', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const convos = await (prisma as any).conversation.findMany({
			where: {
				participants: { some: { id: me } },
				isGroup: false,
				pulseId: null,
			},
			orderBy: { updatedAt: 'desc' },
			include: {
				participants: { select: { id: true, displayName: true, profileImageUrl: true } },
			},
		});
		res.json(
			convos.map((c: any) => ({
				id: c.id,
				participants: c.participants,
				updatedAt: c.updatedAt,
				createdAt: c.createdAt,
				lastMessageText: c.lastMessageText,
				lastSenderId: c.lastSenderId,
				isGroup: c.isGroup,
				name: c.name || null,
				avatarUrl: c.avatarUrl || null,
				pulseId: c.pulseId,
			}))
		);
	} catch (e) {
		console.error('list direct conversations error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

// List my pulse group chat conversations only
router.get('/conversations-pulse', authenticateUser, async (req, res) => {
	try {
		const me = req.user.id as string;
		const convos = await (prisma as any).conversation.findMany({
			where: {
				participants: { some: { id: me } },
				pulseId: { not: null },
			},
			orderBy: { updatedAt: 'desc' },
			include: {
				participants: { select: { id: true, displayName: true, profileImageUrl: true } },
				pulse: { select: { id: true, title: true, imageUrl: true } },
			},
		});
		res.json(
			convos.map((c: any) => ({
				id: c.id,
				participants: c.participants,
				updatedAt: c.updatedAt,
				createdAt: c.createdAt,
				lastMessageText: c.lastMessageText,
				lastSenderId: c.lastSenderId,
				isGroup: true,
				name: c.name || c.pulse?.title || null,
				avatarUrl: c.avatarUrl || c.pulse?.imageUrl || null,
				pulseId: c.pulseId,
			}))
		);
	} catch (e) {
		console.error('list pulse conversations error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});

	// ===================== NEW SEPARATED MODELS ENDPOINTS =====================
	// DirectConversation (1:1 or non-pulse small chats)

	// Create or get a direct conversation (separate model)
	router.post('/direct-conversations/with/:otherUserId', authenticateUser, async (req, res) => {
		try {
			const otherUserId = req.params.otherUserId;
			const me = req.user.id as string;
			if (otherUserId === me) return res.status(400).json({ error: 'Cannot create conversation with yourself' });

			// Look for existing direct conversation between the two participants
			let convo = await (prisma as any).directConversation.findFirst({
				where: {
					AND: [
						{ participants: { some: { id: me } } },
						{ participants: { some: { id: otherUserId } } },
					],
				},
				include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
			});

				if (!convo) {
					convo = await (prisma as any).directConversation.create({
						data: { participants: { connect: [{ id: me }, { id: otherUserId }] } },
						include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
					});
				}

				// Ensure a legacy Conversation exists with the same id for message compatibility
				try {
					const legacy = await (prisma as any).conversation.findUnique({ where: { id: convo.id } });
					if (!legacy) {
						await (prisma as any).conversation.create({
							data: {
								id: convo.id,
								isGroup: false,
								participants: { connect: [{ id: me }, { id: otherUserId }] },
								name: convo.name ?? null,
								avatarUrl: convo.avatarUrl ?? null,
							},
						});
					}
				} catch (e) { console.warn('legacy conversation ensure failed (direct)', e); }

			// Normalize response shape similar to existing /conversations mapping
			const mapped = {
				id: convo.id,
				participants: convo.participants,
				updatedAt: convo.updatedAt,
				createdAt: convo.createdAt,
				lastMessageText: convo.lastMessageText,
				lastSenderId: convo.lastSenderId,
				isGroup: false,
				name: convo.name || null,
				avatarUrl: convo.avatarUrl || null,
				pulseId: null,
				type: 'direct',
			};
			res.json(mapped);
		} catch (e) {
			console.error('direct create/get error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// List my direct conversations (separate model)
	router.get('/direct-conversations', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const convos = await (prisma as any).directConversation.findMany({
				where: { participants: { some: { id: me } } },
				orderBy: { updatedAt: 'desc' },
				include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
			});
			res.json(
				convos.map((c: any) => ({
					id: c.id,
					participants: c.participants,
					updatedAt: c.updatedAt,
					createdAt: c.createdAt,
					lastMessageText: c.lastMessageText,
					lastSenderId: c.lastSenderId,
					isGroup: false,
					name: c.name || null,
					avatarUrl: c.avatarUrl || null,
					pulseId: null,
					type: 'direct',
				}))
			);
		} catch (e) {
			console.error('list direct (new) error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// PulseConversation (group chats scoped to pulses)

	// Get or create a pulse conversation by pulseId (separate model)
	router.post('/pulse-conversations/by-pulse/:pulseId', authenticateUser, async (req, res) => {
		try {
			const { pulseId } = req.params as { pulseId: string };
			const me = req.user.id as string;
			if (!pulseId) return res.status(400).json({ error: 'pulseId required' });

			let convo = await (prisma as any).pulseConversation.findUnique({
				where: { pulseId },
				include: {
					participants: { select: { id: true, displayName: true, profileImageUrl: true } },
					pulse: { select: { id: true, title: true, imageUrl: true } },
				},
			});

				if (!convo) {
				// Create and connect the requester as participant
				convo = await (prisma as any).pulseConversation.create({
					data: {
						pulse: { connect: { id: pulseId } },
						participants: { connect: { id: me } },
						name: undefined,
					},
					include: {
						participants: { select: { id: true, displayName: true, profileImageUrl: true } },
						pulse: { select: { id: true, title: true, imageUrl: true } },
					},
				});
					// Ensure legacy Conversation exists with same id
					try {
						const legacy = await (prisma as any).conversation.findUnique({ where: { id: convo.id } });
						if (!legacy) {
							await (prisma as any).conversation.create({
								data: {
									id: convo.id,
									isGroup: true,
									pulse: { connect: { id: pulseId } },
									participants: { connect: { id: me } },
									name: convo.name ?? undefined,
									avatarUrl: convo.avatarUrl ?? undefined,
								},
							});
						}
					} catch (e) { console.warn('legacy conversation ensure failed (pulse create)', e); }
				} else {
				// Ensure the requester is included as a participant
				const isParticipant = (convo.participants as any[]).some((p: any) => p.id === me);
				if (!isParticipant) {
					await (prisma as any).pulseConversation.update({
						where: { id: convo.id },
						data: { participants: { connect: { id: me } } },
					});
					// reload minimal participants
					const updated = await (prisma as any).pulseConversation.findUnique({
						where: { id: convo.id },
						include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } }, pulse: { select: { id: true, title: true, imageUrl: true } } },
					});
					convo = updated ?? convo;
				}
					// Ensure legacy Conversation exists and connects pulse
					try {
						const legacy = await (prisma as any).conversation.findUnique({ where: { id: convo.id } });
						if (!legacy) {
							await (prisma as any).conversation.create({
								data: {
									id: convo.id,
									isGroup: true,
									pulse: { connect: { id: pulseId } },
									participants: { connect: { id: me } },
									name: convo.name ?? undefined,
									avatarUrl: convo.avatarUrl ?? undefined,
								},
							});
						}
					} catch (e) { console.warn('legacy conversation ensure failed (pulse fetch)', e); }
			}

			const mapped = {
				id: convo.id,
				participants: convo.participants,
				updatedAt: convo.updatedAt,
				createdAt: convo.createdAt,
				lastMessageText: convo.lastMessageText,
				lastSenderId: convo.lastSenderId,
				isGroup: true,
				name: convo.name || (convo.pulse?.title ?? null),
				avatarUrl: convo.avatarUrl || (convo.pulse?.imageUrl ?? null),
				pulseId: convo.pulseId,
				type: 'pulse',
			};
			res.json(mapped);
		} catch (e) {
			console.error('pulse conversation get/create error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// List my pulse conversations (separate model)
	router.get('/pulse-conversations', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;

			// 1) Get pulses the user participates in OR authored by the user
			const myPulses = await prisma.pulse.findMany({
				where: {
					OR: [
						{ participants: { some: { id: me } } },
						{ authorId: me },
					],
				},
				select: { id: true, title: true, imageUrl: true },
				take: 200,
			});
			const pulseIds = myPulses.map(p => p.id);

			// 2) Fetch existing PulseConversations for these pulses
			let convos: any[] = [];
			if (pulseIds.length) {
				convos = await (prisma as any).pulseConversation.findMany({
					where: { pulseId: { in: pulseIds } },
					include: {
						participants: { select: { id: true, displayName: true, profileImageUrl: true } },
						pulse: { select: { id: true, title: true, imageUrl: true } },
					},
				});
			}

			const byPulseId = new Map<string, any>(convos.map((c: any) => [c.pulseId, c]));
			const toEnsureCreate = pulseIds.filter(pid => !byPulseId.has(pid));

			// 3) Create missing conversations for pulses
			for (const pid of toEnsureCreate) {
				try {
					const created = await (prisma as any).pulseConversation.create({
						data: { pulse: { connect: { id: pid } }, participants: { connect: { id: me } } },
						include: {
							participants: { select: { id: true, displayName: true, profileImageUrl: true } },
							pulse: { select: { id: true, title: true, imageUrl: true } },
						},
					});
					convos.push(created);
					byPulseId.set(pid, created);
					// Keep legacy Conversation compatible
					try {
						const legacy = await (prisma as any).conversation.findUnique({ where: { id: created.id } });
						if (!legacy) {
							await (prisma as any).conversation.create({
								data: {
									id: created.id,
									isGroup: true,
									pulse: { connect: { id: pid } },
									participants: { connect: { id: me } },
									name: created.name ?? undefined,
									avatarUrl: created.avatarUrl ?? undefined,
								},
							});
						}
					} catch (_) {}
				} catch (e) {
					console.warn('create pulseConversation failed for pulse', pid, e);
				}
			}

			// 4) Ensure user is participant in each convo they are in
			for (const c of convos) {
				const isParticipant = (c.participants as any[]).some((p: any) => p.id === me);
				if (!isParticipant) {
					try {
						await (prisma as any).pulseConversation.update({
							where: { id: c.id },
							data: { participants: { connect: { id: me } } },
						});
						c.participants.push({ id: me });
					} catch (_) {}
				}
			}

			// 5) Sort by updatedAt desc (fallback to createdAt)
			convos.sort((a: any, b: any) => {
				const ta = new Date(a.updatedAt || a.createdAt).getTime();
				const tb = new Date(b.updatedAt || b.createdAt).getTime();
				return tb - ta;
			});

			res.json(
				convos.map((c: any) => ({
					id: c.id,
					participants: c.participants,
					updatedAt: c.updatedAt,
					createdAt: c.createdAt,
					lastMessageText: c.lastMessageText,
					lastSenderId: c.lastSenderId,
					isGroup: true,
					name: c.name || c.pulse?.title || null,
					avatarUrl: c.avatarUrl || c.pulse?.imageUrl || null,
					pulseId: c.pulseId,
					type: 'pulse',
				}))
			);
		} catch (e) {
			console.error('list pulse (new) error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// GroupConversation (normal group chats not tied to pulses)

	// Create a new group conversation
	router.post('/group-conversations', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { name, description, avatarUrl, initialParticipantIds } = req.body as {
				name?: string;
				description?: string;
				avatarUrl?: string;
				initialParticipantIds?: string[];
			};

			if (!name || name.trim().length === 0) {
				return res.status(400).json({ error: 'Group name is required' });
			}

			// Prepare participants: creator + initial members (deduplicated)
			const participantIds = new Set<string>([me]);
			if (Array.isArray(initialParticipantIds)) {
				initialParticipantIds.forEach(id => {
					if (id && typeof id === 'string') participantIds.add(id);
				});
			}

			const convo = await (prisma as any).groupConversation.create({
				data: {
					name: name.trim(),
					description: description?.trim() || null,
					avatarUrl: avatarUrl || null,
					creator: { connect: { id: me } },
					participants: {
						connect: Array.from(participantIds).map(id => ({ id }))
					}
				},
				include: {
					participants: { select: { id: true, displayName: true, profileImageUrl: true } },
					creator: { select: { id: true, displayName: true } }
				}
			});

			// Ensure legacy Conversation exists with same id for message compatibility
			try {
				const legacy = await (prisma as any).conversation.findUnique({ where: { id: convo.id } });
				if (!legacy) {
					await (prisma as any).conversation.create({
						data: {
							id: convo.id,
							isGroup: true,
							participants: {
								connect: Array.from(participantIds).map(id => ({ id }))
							},
							name: convo.name,
							avatarUrl: convo.avatarUrl || null,
						},
					});
				}
			} catch (e) {
				console.warn('legacy conversation ensure failed (group create)', e);
			}

			const mapped = {
				id: convo.id,
				name: convo.name,
				description: convo.description,
				avatarUrl: convo.avatarUrl,
				creatorId: convo.creatorId,
				creator: convo.creator,
				participants: convo.participants,
				createdAt: convo.createdAt,
				updatedAt: convo.updatedAt,
				lastMessageText: convo.lastMessageText,
				lastSenderId: convo.lastSenderId,
				isGroup: true,
				type: 'group',
			};

			res.status(201).json(mapped);
		} catch (e) {
			console.error('create group conversation error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Get a specific group conversation
	router.get('/group-conversations/:id', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;

			const convo = await (prisma as any).groupConversation.findUnique({
				where: { id },
				include: {
					participants: { select: { id: true, displayName: true, profileImageUrl: true } },
					creator: { select: { id: true, displayName: true } }
				}
			});

			if (!convo) {
				return res.status(404).json({ error: 'Group conversation not found' });
			}

			const isParticipant = (convo.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) {
				return res.status(403).json({ error: 'Forbidden' });
			}

			const mapped = {
				id: convo.id,
				name: convo.name,
				description: convo.description,
				avatarUrl: convo.avatarUrl,
				creatorId: convo.creatorId,
				creator: convo.creator,
				participants: convo.participants,
				createdAt: convo.createdAt,
				updatedAt: convo.updatedAt,
				lastMessageText: convo.lastMessageText,
				lastSenderId: convo.lastSenderId,
				isGroup: true,
				type: 'group',
			};

			res.json(mapped);
		} catch (e) {
			console.error('get group conversation error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// List my group conversations
	router.get('/group-conversations', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;

			const convos = await (prisma as any).groupConversation.findMany({
				where: { participants: { some: { id: me } } },
				orderBy: { updatedAt: 'desc' },
				include: {
					participants: { select: { id: true, displayName: true, profileImageUrl: true } },
					creator: { select: { id: true, displayName: true } }
				}
			});

			const mapped = convos.map((c: any) => ({
				id: c.id,
				name: c.name,
				description: c.description,
				avatarUrl: c.avatarUrl,
				creatorId: c.creatorId,
				creator: c.creator,
				participants: c.participants,
				createdAt: c.createdAt,
				updatedAt: c.updatedAt,
				lastMessageText: c.lastMessageText,
				lastSenderId: c.lastSenderId,
				isGroup: true,
				type: 'group',
			}));

			res.json(mapped);
		} catch (e) {
			console.error('list group conversations error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Invite members to a group conversation
	router.post('/group-conversations/:id/invite', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;
			const { userIds } = req.body as { userIds?: string[] };

			if (!Array.isArray(userIds) || userIds.length === 0) {
				return res.status(400).json({ error: 'userIds required' });
			}

			const convo = await (prisma as any).groupConversation.findUnique({
				where: { id },
				include: { participants: true }
			});

			if (!convo) {
				return res.status(404).json({ error: 'Group conversation not found' });
			}

			const isParticipant = convo.participants.some((p: any) => p.id === me);
			if (!isParticipant) {
				return res.status(403).json({ error: 'Forbidden' });
			}

			const created: any[] = [];
			for (const targetId of userIds) {
				if (!targetId || targetId === me) continue;

				const alreadyParticipant = convo.participants.some((p: any) => p.id === targetId);
				if (alreadyParticipant) continue;

				try {
					// Check if invitation already exists
					const existingInvite = await prisma.conversationInvitation.findFirst({
						where: {
							conversationId: id,
							inviteeId: targetId,
							status: 'PENDING'
						}
					});

					const invite = existingInvite
						? await prisma.conversationInvitation.update({
								where: { id: existingInvite.id },
								data: { status: 'PENDING', invitationType: 'GROUP_CHAT' }
							})
						: await prisma.conversationInvitation.create({
								data: {
									conversationId: id,
									inviterId: me,
									inviteeId: targetId,
									invitationType: 'GROUP_CHAT'
								}
							});

					// Create notification for invitee
					await prisma.notification.create({
						data: {
							userId: targetId,
							type: 'INVITE',
							title: 'Group Chat Invitation',
							message: `You have been invited to join "${convo.name}"`,
							data: {
								conversationId: id,
								inviterId: me,
								invitationId: invite.id,
								conversationType: 'group'
							},
						},
					});

					created.push(invite);
				} catch (e) {
					console.error('Group invite create error', e);
				}
			}

			res.json({ ok: true, created });
		} catch (e) {
			console.error('invite to group conversation error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Update group conversation settings (name, description, avatar)
	router.patch('/group-conversations/:id', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;
			const { name, description, avatarUrl } = req.body as {
				name?: string;
				description?: string;
				avatarUrl?: string;
			};

			const convo = await (prisma as any).groupConversation.findUnique({
				where: { id },
				include: { participants: true }
			});

			if (!convo) {
				return res.status(404).json({ error: 'Group conversation not found' });
			}

			const isParticipant = convo.participants.some((p: any) => p.id === me);
			if (!isParticipant) {
				return res.status(403).json({ error: 'Forbidden' });
			}

			const updateData: any = {};
			if (name !== undefined && name.trim().length > 0) {
				updateData.name = name.trim();
			}
			if (description !== undefined) {
				updateData.description = description?.trim() || null;
			}
			if (avatarUrl !== undefined) {
				updateData.avatarUrl = avatarUrl || null;
			}

			const updated = await (prisma as any).groupConversation.update({
				where: { id },
				data: updateData,
				include: {
					participants: { select: { id: true, displayName: true, profileImageUrl: true } },
					creator: { select: { id: true, displayName: true } }
				}
			});

			// Also update legacy conversation
			try {
				await (prisma as any).conversation.update({
					where: { id },
					data: {
						name: updated.name,
						avatarUrl: updated.avatarUrl,
					}
				});
			} catch (e) {
				console.warn('legacy conversation update failed', e);
			}

			const mapped = {
				id: updated.id,
				name: updated.name,
				description: updated.description,
				avatarUrl: updated.avatarUrl,
				creatorId: updated.creatorId,
				creator: updated.creator,
				participants: updated.participants,
				createdAt: updated.createdAt,
				updatedAt: updated.updatedAt,
				lastMessageText: updated.lastMessageText,
				lastSenderId: updated.lastSenderId,
				isGroup: true,
				type: 'group',
			};

			res.json(mapped);
		} catch (e) {
			console.error('update group conversation error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Leave a group conversation
	router.post('/group-conversations/:id/leave', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;

			const convo = await (prisma as any).groupConversation.findUnique({
				where: { id },
				include: { participants: true }
			});

			if (!convo) {
				return res.status(404).json({ error: 'Group conversation not found' });
			}

			const isParticipant = convo.participants.some((p: any) => p.id === me);
			if (!isParticipant) {
				return res.status(400).json({ error: 'Not a participant' });
			}

			await (prisma as any).groupConversation.update({
				where: { id },
				data: {
					participants: { disconnect: { id: me } }
				}
			});

			// Also disconnect from legacy conversation
			try {
				await (prisma as any).conversation.update({
					where: { id },
					data: {
						participants: { disconnect: { id: me } }
					}
				});
			} catch (e) {
				console.warn('legacy conversation disconnect failed', e);
			}

			res.json({ ok: true, message: 'Left group conversation' });
		} catch (e) {
			console.error('leave group conversation error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Messages for new models (proxy to legacy Conversation messages by shared id)
	router.get('/direct-conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;
			const { cursor, limit = '30' } = req.query as { cursor?: string; limit?: string };
			const take = Math.max(1, Math.min(parseInt(limit as string, 10) || 30, 100));

			const convo = await (prisma as any).directConversation.findUnique({ where: { id }, include: { participants: true } });
			if (!convo) return res.status(404).json({ error: 'Conversation not found' });
			const isParticipant = (convo.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });

			const messages = await prisma.message.findMany({
				where: { conversationId: id },
				orderBy: { createdAt: 'desc' },
				take,
				cursor: cursor ? { id: cursor } : undefined,
				skip: cursor ? 1 : 0,
				include: {
					sender: {
						select: {
							id: true,
							displayName: true,
							profileImageUrl: true,
						}
					},
					repliedTo: {
						select: {
							id: true,
							text: true,
							imageUrl: true,
							videoUrl: true,
							senderId: true,
							sender: {
								select: {
									id: true,
									displayName: true,
								}
							}
						}
					}
				}
			});

			const ids = messages.map(m => m.id);
			let reactions: { messageId: string; emoji: string; userId: string }[] = [];
			if (ids.length) {
				// @ts-ignore - messageReaction available after prisma generate
				reactions = await (prisma as any).messageReaction.findMany({ where: { messageId: { in: ids } }, select: { messageId: true, emoji: true, userId: true } });
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
					senderName: (m as any).sender?.displayName || null,
					senderPhotoUrl: (m as any).sender?.profileImageUrl || null,
					reactions: reactionMap[m.id] || {},
					deliveredTo: m.deliveredTo || [],
					readBy: m.readBy || [],
					repliedTo: (m as any).repliedTo ? {
						id: (m as any).repliedTo.id,
						text: (m as any).repliedTo.text,
						imageUrl: (m as any).repliedTo.imageUrl,
						videoUrl: (m as any).repliedTo.videoUrl,
						senderId: (m as any).repliedTo.senderId,
						senderName: (m as any).repliedTo.sender?.displayName || 'Unknown',
					} : null,
				})),
				nextCursor: messages.length === take ? messages[messages.length - 1].id : null,
			});
		} catch (e) {
			console.error('direct messages list error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	router.get('/pulse-conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;
			const { cursor, limit = '30' } = req.query as { cursor?: string; limit?: string };
			const take = Math.max(1, Math.min(parseInt(limit as string, 10) || 30, 100));

			const pconv = await (prisma as any).pulseConversation.findUnique({ where: { id }, include: { participants: true, pulse: { select: { id: true } } } });
			if (!pconv) return res.status(404).json({ error: 'Conversation not found' });
			const isParticipant = (pconv.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });

			// Resolve legacy Conversation id: prefer same id, else find by pulseId
			let legacyId = id;
			const legacy = await (prisma as any).conversation.findUnique({ where: { id } });
			if (!legacy && pconv.pulse?.id) {
				const byPulse = await (prisma as any).conversation.findFirst({ where: { pulseId: pconv.pulse.id } });
				if (byPulse) legacyId = byPulse.id;
			}

		const messages = await prisma.message.findMany({
			where: { conversationId: legacyId },
			orderBy: { createdAt: 'desc' },
			take,
			cursor: cursor ? { id: cursor } : undefined,
			skip: cursor ? 1 : 0,
			include: {
				sender: {
					select: {
						id: true,
						displayName: true,
						profileImageUrl: true,
					}
				},
				repliedTo: {
					select: {
						id: true,
						text: true,
						imageUrl: true,
						videoUrl: true,
						senderId: true,
						sender: {
							select: {
								id: true,
								displayName: true,
							}
						}
					}
				}
			}
		});			const ids = messages.map(m => m.id);
			let reactions: { messageId: string; emoji: string; userId: string }[] = [];
			if (ids.length) {
				// @ts-ignore - messageReaction available after prisma generate
				reactions = await (prisma as any).messageReaction.findMany({ where: { messageId: { in: ids } }, select: { messageId: true, emoji: true, userId: true } });
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
					senderName: (m as any).sender?.displayName || null,
					senderPhotoUrl: (m as any).sender?.profileImageUrl || null,
					reactions: reactionMap[m.id] || {},
					deliveredTo: m.deliveredTo || [],
					readBy: m.readBy || [],
					repliedTo: (m as any).repliedTo ? {
						id: (m as any).repliedTo.id,
						text: (m as any).repliedTo.text,
						imageUrl: (m as any).repliedTo.imageUrl,
						videoUrl: (m as any).repliedTo.videoUrl,
						senderId: (m as any).repliedTo.senderId,
						senderName: (m as any).repliedTo.sender?.displayName || 'Unknown',
					} : null,
				})),
				nextCursor: messages.length === take ? messages[messages.length - 1].id : null,
			});
		} catch (e) {
			console.error('pulse messages list error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});
	// --- Generic REST send: Post a message to a conversation by id ---
	router.post('/conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params as { id: string };
			const { text, imageUrl, videoUrl } = (req.body || {}) as { text?: string; imageUrl?: string; videoUrl?: string };
			if (!text && !imageUrl && !videoUrl) return res.status(400).json({ error: 'text or media required' });

			// Load conversation with participants and (optional) pulse link
			let convo = await (prisma as any).conversation.findUnique({
				where: { id },
				include: { participants: true, pulse: { select: { id: true } } },
			});

			// Fallback: if not found, treat provided id as pulseId and resolve the conversation for that pulse
			if (!convo) {
				const pulse = await prisma.pulse.findUnique({ where: { id } });
				if (pulse) {
					convo = await (prisma as any).conversation.findFirst({ where: { pulseId: id }, include: { participants: true, pulse: { select: { id: true } } } });
				}
			}
			if (!convo) return res.status(404).json({ error: 'Conversation not found' });

			// Ensure caller is participant; if pulse chat, auto-join if user is a pulse member
			let isParticipant = (convo.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant && convo.pulse?.id) {
				try {
					const pulse = await prisma.pulse.findUnique({ where: { id: convo.pulse.id }, include: { participants: { select: { id: true } }, author: { select: { id: true } } } });
					const isPulseMember = !!pulse && (pulse.author.id === me || (pulse.participants as any[]).some((p: any) => p.id === me));
					if (isPulseMember) {
						await (prisma as any).conversation.update({ where: { id: convo.id }, data: { participants: { connect: { id: me } } } });
						isParticipant = true;
					}
				} catch (_) {}
			}
			if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });

				const msg = await (prisma as any).message.create({
				data: { conversationId: convo.id, senderId: me, text: text ?? null, imageUrl: imageUrl ?? null, videoUrl: videoUrl ?? null },
			});
			await (prisma as any).conversation.update({
				where: { id: convo.id },
				data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me },
			});
				// Realtime emit
					try {
						const io = getIo();
						io?.to(`conversation:${convo.id}`).emit('message:new', {
						id: msg.id,
						conversationId: msg.conversationId,
						senderId: msg.senderId,
						text: msg.text,
						imageUrl: msg.imageUrl,
						createdAt: msg.createdAt,
						videoUrl: msg.videoUrl,
					});
						// Emit conversation updates only (message already sent to room above)
						(convo.participants as any[]).forEach((p: any) => {
						const sockets = userSockets.get(p.id);
						if (!sockets) return;
							sockets.forEach((sid: string) => {
								io?.to(sid).emit('conversation:updated', { conversationId: convo.id });
							});
					});
				} catch (_) {}
			// Mirror last message metadata where possible for split models (best-effort)
			try {
				await (prisma as any).directConversation.update({ where: { id: convo.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } }).catch(() => null);
				await (prisma as any).pulseConversation.update({ where: { id: convo.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } }).catch(() => null);
			} catch (_) {}

			return res.status(201).json({ message: msg });
		} catch (e) {
			console.error('conversation message post error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Proxy variants for separated models
	router.post('/pulse-conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params as { id: string };
			const { text, imageUrl, videoUrl } = (req.body || {}) as { text?: string; imageUrl?: string; videoUrl?: string };
			if (!text && !imageUrl && !videoUrl) return res.status(400).json({ error: 'text or media required' });
			// Load PulseConversation with context
			const pconv = await (prisma as any).pulseConversation.findUnique({ where: { id }, include: { participants: true, pulse: { select: { id: true, title: true, imageUrl: true } } } });
			if (!pconv) return res.status(404).json({ error: 'Conversation not found' });
			const isParticipant = (pconv.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });

			// Resolve or create legacy Conversation backing this pulse chat
			let legacy = await (prisma as any).conversation.findUnique({ where: { id } });
			if (!legacy && pconv.pulse?.id) {
				legacy = await (prisma as any).conversation.findFirst({ where: { pulseId: pconv.pulse.id } });
			}
			if (!legacy) {
				// Create a legacy conversation linked to this pulse
				legacy = await (prisma as any).conversation.create({
					data: {
						isGroup: true,
						pulse: { connect: { id: pconv.pulse.id } },
						name: pconv.pulse?.title ?? null,
						avatarUrl: pconv.pulse?.imageUrl ?? null,
						participants: { connect: (pconv.participants as any[]).map((u: any) => ({ id: u.id })) },
					},
				});
			}

			const msg = await (prisma as any).message.create({ data: { conversationId: legacy.id, senderId: me, text: text ?? null, imageUrl: imageUrl ?? null, videoUrl: videoUrl ?? null } });
			await (prisma as any).conversation.update({ where: { id: legacy.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } });
			await (prisma as any).pulseConversation.update({ where: { id: pconv.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } }).catch(() => null);
					try {
						const io = getIo();
						io?.to(`conversation:${legacy.id}`).emit('message:new', { id: msg.id, conversationId: legacy.id, senderId: me, text: msg.text, imageUrl: msg.imageUrl, createdAt: msg.createdAt, videoUrl: msg.videoUrl });
						(pconv.participants as any[]).forEach((p: any) => {
						const sockets = userSockets.get(p.id);
						if (!sockets) return;
							sockets.forEach((sid: string) => {
								io?.to(sid).emit('conversation:updated', { conversationId: legacy.id });
							});
					});
				} catch (_) {}
			res.status(201).json({ message: msg });
		} catch (e) {
			console.error('pulse-conversation message post error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	router.post('/direct-conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params as { id: string };
			const { text, imageUrl, videoUrl } = (req.body || {}) as { text?: string; imageUrl?: string; videoUrl?: string };
			if (!text && !imageUrl && !videoUrl) return res.status(400).json({ error: 'text or media required' });
			const dconv = await (prisma as any).directConversation.findUnique({ where: { id }, include: { participants: true } });
			if (!dconv) return res.status(404).json({ error: 'Conversation not found' });
			const isParticipant = (dconv.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) return res.status(403).json({ error: 'Forbidden' });
			// Ensure legacy Conversation exists/resolve id
			let legacy = await (prisma as any).conversation.findUnique({ where: { id } });
			if (!legacy) {
				legacy = await (prisma as any).conversation.create({
					data: {
						id, // reuse the direct conversation id to keep them aligned
						isGroup: false,
						participants: { connect: (dconv.participants as any[]).map((u: any) => ({ id: u.id })) },
						name: dconv.name ?? null,
						avatarUrl: dconv.avatarUrl ?? null,
					},
				});
			}
			const msg = await (prisma as any).message.create({ data: { conversationId: legacy.id, senderId: me, text: text ?? null, imageUrl: imageUrl ?? null, videoUrl: videoUrl ?? null } });
			await (prisma as any).conversation.update({ where: { id: legacy.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } });
			await (prisma as any).directConversation.update({ where: { id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } }).catch(() => null);
					try {
						const io = getIo();
						io?.to(`conversation:${legacy.id}`).emit('message:new', { id: msg.id, conversationId: legacy.id, senderId: me, text: msg.text, imageUrl: msg.imageUrl, createdAt: msg.createdAt, videoUrl: msg.videoUrl });
						(dconv.participants as any[]).forEach((p: any) => {
						const sockets = userSockets.get(p.id);
						if (!sockets) return;
							sockets.forEach((sid: string) => {
								io?.to(sid).emit('conversation:updated', { conversationId: legacy.id });
							});
					});
				} catch (_) {}
			res.status(201).json({ message: msg });
		} catch (e) {
			console.error('direct-conversation message post error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});

	// Get messages for a group conversation
	router.get('/group-conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;
			const { cursor, limit = '30' } = req.query as { cursor?: string; limit?: string };
			const take = Math.max(1, Math.min(parseInt(limit as string, 10) || 30, 100));

			const convo = await (prisma as any).groupConversation.findUnique({
				where: { id },
				include: { participants: true }
			});

			if (!convo) {
				return res.status(404).json({ error: 'Conversation not found' });
			}

			const isParticipant = (convo.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) {
				return res.status(403).json({ error: 'Forbidden' });
			}

		const messages = await prisma.message.findMany({
			where: { conversationId: id },
			orderBy: { createdAt: 'desc' },
			take,
			cursor: cursor ? { id: cursor } : undefined,
			skip: cursor ? 1 : 0,
			include: {
				sender: {
					select: {
						id: true,
						displayName: true,
						profileImageUrl: true,
					}
				},
				repliedTo: {
					select: {
						id: true,
						text: true,
						imageUrl: true,
						videoUrl: true,
						senderId: true,
						sender: {
							select: {
								id: true,
								displayName: true,
							}
						}
					}
				}
			}
		});			const ids = messages.map(m => m.id);
			let reactions: { messageId: string; emoji: string; userId: string }[] = [];
			if (ids.length) {
				reactions = await (prisma as any).messageReaction.findMany({
					where: { messageId: { in: ids } },
					select: { messageId: true, emoji: true, userId: true }
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
				senderName: (m as any).sender?.displayName || null,
				senderPhotoUrl: (m as any).sender?.profileImageUrl || null,
				reactions: reactionMap[m.id] || {},
				deliveredTo: m.deliveredTo || [],
				readBy: m.readBy || [],
				repliedTo: (m as any).repliedTo ? {
					id: (m as any).repliedTo.id,
					text: (m as any).repliedTo.text,
					imageUrl: (m as any).repliedTo.imageUrl,
					videoUrl: (m as any).repliedTo.videoUrl,
					senderId: (m as any).repliedTo.senderId,
					senderName: (m as any).repliedTo.sender?.displayName || 'Unknown',
				} : null,
			})),
			nextCursor: messages.length === take ? messages[messages.length - 1].id : null,
		});
	} catch (e) {
		console.error('group conversation messages list error', e);
		res.status(500).json({ error: 'Internal server error' });
	}
});	// Post a message to a group conversation
	router.post('/group-conversations/:id/messages', authenticateUser, async (req, res) => {
		try {
			const me = req.user.id as string;
			const { id } = req.params;
			const { text, imageUrl, videoUrl } = req.body as {
				text?: string;
				imageUrl?: string;
				videoUrl?: string;
			};

			if (!text && !imageUrl && !videoUrl) {
				return res.status(400).json({ error: 'text or media required' });
			}

			const convo = await (prisma as any).groupConversation.findUnique({
				where: { id },
				include: { participants: true }
			});

			if (!convo) {
				return res.status(404).json({ error: 'Conversation not found' });
			}

			const isParticipant = (convo.participants as any[]).some((p: any) => p.id === me);
			if (!isParticipant) {
				return res.status(403).json({ error: 'Forbidden' });
			}

			// Ensure legacy Conversation exists
			let legacy = await (prisma as any).conversation.findUnique({ where: { id } });
			if (!legacy) {
				legacy = await (prisma as any).conversation.create({
					data: {
						id,
						isGroup: true,
						participants: {
							connect: (convo.participants as any[]).map((u: any) => ({ id: u.id }))
						},
						name: convo.name,
						avatarUrl: convo.avatarUrl || null,
					},
				});
			}

			const msg = await (prisma as any).message.create({
				data: {
					conversationId: legacy.id,
					senderId: me,
					text: text ?? null,
					imageUrl: imageUrl ?? null,
					videoUrl: videoUrl ?? null
				}
			});

			const lastMessageText = text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : ''));

			await (prisma as any).conversation.update({
				where: { id: legacy.id },
				data: {
					updatedAt: new Date(),
					lastMessageText,
					lastSenderId: me
				}
			});

			await (prisma as any).groupConversation.update({
				where: { id },
				data: {
					updatedAt: new Date(),
					lastMessageText,
					lastSenderId: me
				}
			}).catch(() => null);

			// Emit realtime updates
			try {
				const io = getIo();
				io?.to(`conversation:${legacy.id}`).emit('message:new', {
					id: msg.id,
					conversationId: legacy.id,
					senderId: me,
					text: msg.text,
					imageUrl: msg.imageUrl,
					createdAt: msg.createdAt,
					videoUrl: msg.videoUrl
				});

				// Notify participants of conversation update (removed duplicate message:new)
				(convo.participants as any[]).forEach((p: any) => {
					const sockets = userSockets.get(p.id);
					if (!sockets) return;
					sockets.forEach((sid: string) => {
						io?.to(sid).emit('conversation:updated', {
							conversationId: legacy.id
						});
					});
				});
			} catch (e) {
				console.warn('realtime emit failed', e);
			}

			res.status(201).json({ message: msg });
		} catch (e) {
			console.error('group conversation message post error', e);
			res.status(500).json({ error: 'Internal server error' });
		}
	});




