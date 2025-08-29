import express from 'express';
import admin from '../firebase';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const router = express.Router();

router.post('/', async (req, res) => {
  console.log('Received auth request');
  const authHeader = req.headers.authorization;
  console.log('Authorization header:', authHeader);
  if (!authHeader?.startsWith('Bearer ')) {
    console.log('Missing or invalid token');
    return res.status(401).send('Missing or invalid token');
  }

  const idToken = authHeader.split(' ')[1];
  console.log('ID Token:', idToken);

  try {
    console.log('Verifying ID token...');
    const decoded = await admin.auth().verifyIdToken(idToken);
    console.log('Decoded token:', decoded);
    const { uid, email, name, picture } = decoded;

    console.log('Looking up user with firebaseUid:', uid);
    let user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
    console.log('User lookup result:', user);

    if (!user) {
      console.log('User not found, creating new user...');
      // Ensure email is unique by always using the Firebase UID in the email
      // This prevents conflicts with the @unique constraint on the email field
      const emailToUse = email && email.trim() !== '' ? `${uid}+${email}` : `${uid}@placeholder.com`;
      user = await prisma.user.create({
        data: {
          id: uid,
          firebaseUid: uid,
          email: emailToUse,
          displayName: name ?? '',
        },
      });
      console.log('Created user:', user);
    } else {
      console.log('User already exists');
    }

    res.json({ user });
  } catch (err) {
    console.error('Error in auth route:', err);
    // Send a more detailed error message for debugging
    if (err instanceof Error) {
      res.status(500).json({ error: 'Internal server error', details: err.message });
    } else {
      res.status(500).json({ error: 'Internal server error', details: String(err) });
    }
  }
});

export default router;
