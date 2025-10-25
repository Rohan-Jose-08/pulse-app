import { Router, Request, Response } from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticateUser } from '../middleware/auth';

const router = Router();
const prisma = new PrismaClient();

// GET /api/highlights/pulse/:pulseId - Get all highlights for a specific pulse
router.get('/pulse/:pulseId', async (req: Request, res: Response) => {
  try {
    const { pulseId } = req.params;

    const highlights = await prisma.highlight.findMany({
      where: { pulseId },
      include: {
        user: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json(highlights);
  } catch (error) {
    console.error('Error fetching pulse highlights:', error);
    res.status(500).json({ error: 'Failed to fetch highlights' });
  }
});

// GET /api/highlights/user/:userId - Get all highlights created by a user
router.get('/user/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const highlights = await prisma.highlight.findMany({
      where: { userId, isPublic: true },
      include: {
        pulse: {
          select: {
            id: true,
            title: true,
            eventTime: true,
          },
        },
        user: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json(highlights);
  } catch (error) {
    console.error('Error fetching user highlights:', error);
    res.status(500).json({ error: 'Failed to fetch highlights' });
  }
});

// GET /api/highlights/:id - Get a specific highlight
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const highlight = await prisma.highlight.findUnique({
      where: { id },
      include: {
        user: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
        pulse: {
          select: {
            id: true,
            title: true,
            description: true,
            eventTime: true,
            location: {
              select: {
                name: true,
                city: true,
                country: true,
              },
            },
          },
        },
      },
    });

    if (!highlight) {
      return res.status(404).json({ error: 'Highlight not found' });
    }

    // Increment view count
    await prisma.highlight.update({
      where: { id },
      data: { viewCount: { increment: 1 } },
    });

    res.json(highlight);
  } catch (error) {
    console.error('Error fetching highlight:', error);
    res.status(500).json({ error: 'Failed to fetch highlight' });
  }
});

// POST /api/highlights - Create a new highlight (video must be uploaded to storage first)
router.post('/', authenticateUser, async (req: any, res: Response) => {
  try {
    const { videoUrl, thumbnailUrl, duration, caption, pulseId, isPublic } = req.body;
    const userId = req.user.id;

    if (!videoUrl || !duration || !pulseId) {
      return res.status(400).json({ 
        error: 'videoUrl, duration, and pulseId are required' 
      });
    }

    // Verify the pulse exists and user has access
    const pulse = await prisma.pulse.findUnique({
      where: { id: pulseId },
      include: {
        participants: {
          where: { id: userId },
        },
      },
    });

    if (!pulse) {
      return res.status(404).json({ error: 'Pulse not found' });
    }

    // Check if user is author or participant
    const isAuthor = pulse.authorId === userId;
    const isParticipant = pulse.participants.length > 0;

    if (!isAuthor && !isParticipant) {
      return res.status(403).json({ 
        error: 'You must be a participant or author of the pulse to create highlights' 
      });
    }

    const highlight = await prisma.highlight.create({
      data: {
        videoUrl,
        thumbnailUrl: thumbnailUrl || null,
        duration: parseInt(duration),
        caption: caption || null,
        pulseId,
        userId,
        isPublic: isPublic !== undefined ? isPublic : true,
      },
      include: {
        user: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
        pulse: {
          select: {
            id: true,
            title: true,
          },
        },
      },
    });

    res.status(201).json(highlight);
  } catch (error) {
    console.error('Error creating highlight:', error);
    res.status(500).json({ error: 'Failed to create highlight' });
  }
});

// PATCH /api/highlights/:id - Update a highlight (caption or visibility)
router.patch('/:id', authenticateUser, async (req: any, res: Response) => {
  try {
    const { id } = req.params;
    const { caption, isPublic } = req.body;
    const userId = req.user.id;

    // Check if the highlight belongs to the user
    const existingHighlight = await prisma.highlight.findUnique({
      where: { id },
    });

    if (!existingHighlight) {
      return res.status(404).json({ error: 'Highlight not found' });
    }

    if (existingHighlight.userId !== userId) {
      return res.status(403).json({ error: 'Not authorized to update this highlight' });
    }

    const updateData: any = {};
    
    if (caption !== undefined) {
      updateData.caption = caption;
    }
    
    if (isPublic !== undefined) {
      updateData.isPublic = isPublic;
    }

    const updatedHighlight = await prisma.highlight.update({
      where: { id },
      data: updateData,
      include: {
        user: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
        pulse: {
          select: {
            id: true,
            title: true,
          },
        },
      },
    });

    res.json(updatedHighlight);
  } catch (error) {
    console.error('Error updating highlight:', error);
    res.status(500).json({ error: 'Failed to update highlight' });
  }
});

// DELETE /api/highlights/:id - Delete a highlight
router.delete('/:id', authenticateUser, async (req: any, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    // Check if the highlight belongs to the user
    const existingHighlight = await prisma.highlight.findUnique({
      where: { id },
    });

    if (!existingHighlight) {
      return res.status(404).json({ error: 'Highlight not found' });
    }

    if (existingHighlight.userId !== userId) {
      return res.status(403).json({ error: 'Not authorized to delete this highlight' });
    }

    await prisma.highlight.delete({
      where: { id },
    });

    res.json({ success: true, message: 'Highlight deleted successfully' });
  } catch (error) {
    console.error('Error deleting highlight:', error);
    res.status(500).json({ error: 'Failed to delete highlight' });
  }
});

export default router;
