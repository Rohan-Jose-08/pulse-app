import * as admin from 'firebase-admin';
import * as path from 'path';

admin.initializeApp({
  credential: admin.credential.cert(
    path.resolve(__dirname, '../firebase-admin-key.json')
  ),
});

export default admin;