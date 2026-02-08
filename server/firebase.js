const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

let db = null;

try {
  const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');

  if (fs.existsSync(serviceAccountPath)) {
    // Local development: use service account file
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('Firebase Admin initialized with service account file');
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    // Production: use environment variable
    admin.initializeApp({
      credential: admin.credential.applicationDefault()
    });
    console.log('Firebase Admin initialized with application default credentials');
  } else {
    console.warn('Firebase: No credentials found. Firestore sync will be disabled.');
    console.warn('  - Place serviceAccountKey.json in server/ for local dev');
    console.warn('  - Or set GOOGLE_APPLICATION_CREDENTIALS env var for production');
  }

  if (admin.apps.length > 0) {
    db = admin.firestore();
  }
} catch (error) {
  console.error('Firebase initialization failed:', error.message);
  console.warn('Firestore sync will be disabled. Racing will still work via Socket.IO.');
}

module.exports = { admin, db };
