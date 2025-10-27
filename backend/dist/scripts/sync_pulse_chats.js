"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Backfill/sync script: Ensure each Pulse has a group chat (Conversation) and that
 * all pulse participants (including the author) are members of that chat.
 * Also ensures a PulseConversation record exists with the same id for compatibility
 * with separated conversation models.
 */
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
async function main() {
    const pulses = await prisma.pulse.findMany({
        include: { participants: { select: { id: true } }, author: { select: { id: true } } },
        orderBy: { createdAt: 'asc' },
        take: 10000,
    });
    let created = 0;
    let updated = 0;
    let ensuredPulseConv = 0;
    for (const p of pulses) {
        const memberIds = new Set([p.author.id, ...p.participants.map((u) => u.id)]);
        // 1) Ensure legacy Conversation (group chat) exists and is attached to this pulse
        let convo = await prisma.conversation.findFirst({
            where: { pulseId: p.id },
            include: { participants: { select: { id: true } } },
        });
        if (!convo) {
            convo = await prisma.conversation.create({
                data: {
                    pulse: { connect: { id: p.id } },
                    isGroup: true,
                    name: p.title,
                    avatarUrl: p.imageUrl ?? null,
                    participants: { connect: Array.from(memberIds).map((id) => ({ id })) },
                },
                include: { participants: { select: { id: true } } },
            });
            created++;
        }
        else {
            // Sync metadata
            const metaUpdates = {};
            if (convo.name !== p.title)
                metaUpdates.name = p.title;
            if (convo.avatarUrl !== (p.imageUrl ?? null))
                metaUpdates.avatarUrl = p.imageUrl ?? null;
            if (Object.keys(metaUpdates).length) {
                await prisma.conversation.update({ where: { id: convo.id }, data: metaUpdates });
            }
            // Sync missing members
            const existingIds = new Set(convo.participants.map((x) => x.id));
            const toConnect = Array.from(memberIds).filter((id) => !existingIds.has(id));
            if (toConnect.length) {
                await prisma.conversation.update({
                    where: { id: convo.id },
                    data: { participants: { connect: toConnect.map((id) => ({ id })) } },
                });
                updated++;
            }
        }
        // 2) Ensure PulseConversation record exists and mirrors the conversation id
        try {
            let pconv = await prisma.pulseConversation.findUnique({ where: { pulseId: p.id }, include: { participants: { select: { id: true } } } });
            if (!pconv) {
                // Create with the SAME id as the legacy Conversation for compatibility if possible
                const existingLegacy = convo || (await prisma.conversation.findFirst({ where: { pulseId: p.id } }));
                const data = {
                    pulse: { connect: { id: p.id } },
                    participants: { connect: Array.from(memberIds).map((id) => ({ id })) },
                    name: p.title,
                    avatarUrl: p.imageUrl ?? null,
                };
                if (existingLegacy?.id)
                    data.id = existingLegacy.id;
                pconv = await prisma.pulseConversation.create({ data });
                ensuredPulseConv++;
            }
            else {
                const existingIds = new Set(pconv.participants.map((x) => x.id));
                const toConnect = Array.from(memberIds).filter((id) => !existingIds.has(id));
                if (toConnect.length) {
                    await prisma.pulseConversation.update({
                        where: { id: pconv.id },
                        data: { participants: { connect: toConnect.map((id) => ({ id })) } },
                    });
                }
                // Sync metadata if changed
                const meta = {};
                if (pconv.name !== p.title)
                    meta.name = p.title;
                if (pconv.avatarUrl !== (p.imageUrl ?? null))
                    meta.avatarUrl = p.imageUrl ?? null;
                if (Object.keys(meta).length) {
                    await prisma.pulseConversation.update({ where: { id: pconv.id }, data: meta });
                }
            }
        }
        catch (e) {
            // Non-fatal
            console.warn('PulseConversation ensure failed for pulse', p.id, e);
        }
    }
    console.log(JSON.stringify({
        pulsesProcessed: pulses.length,
        conversationsCreated: created,
        conversationsUpdated: updated,
        pulseConversationsEnsured: ensuredPulseConv,
    }, null, 2));
}
main()
    .catch((e) => {
    console.error('sync_pulse_chats error', e);
    process.exit(1);
})
    .finally(async () => {
    await prisma.$disconnect();
});
//# sourceMappingURL=sync_pulse_chats.js.map