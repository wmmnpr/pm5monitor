const { db, admin } = require('./firebase');

// Helper: returns true if Firestore is available
function isEnabled() {
  return db !== null;
}

// ============================================
// LOBBY SYNC
// ============================================

async function syncLobbyCreated(lobby) {
  if (!isEnabled()) return;
  try {
    await db.collection('lobbies').doc(lobby.id).set({
      id: lobby.id,
      creatorId: lobby.creatorId,
      raceDistance: lobby.raceDistance,
      entryFee: lobby.entryFee || '0',
      payoutMode: lobby.payoutMode || 'winner_takes_all',
      status: lobby.status,
      maxParticipants: lobby.maxParticipants,
      minParticipants: lobby.minParticipants,
      participantCount: lobby.participants.length,
      createdAt: lobby.createdAt,
      completedAt: null,
      raceId: null
    });
    console.log(`Firestore: lobby ${lobby.id} created`);
  } catch (error) {
    console.error(`Firestore: failed to sync lobby created:`, error.message);
  }
}

async function syncLobbyStatusUpdate(lobbyId, status, participantCount) {
  if (!isEnabled()) return;
  try {
    await db.collection('lobbies').doc(lobbyId).update({
      status,
      participantCount
    });
    console.log(`Firestore: lobby ${lobbyId} updated -> status=${status}, participants=${participantCount}`);
  } catch (error) {
    console.error(`Firestore: failed to sync lobby status update:`, error.message);
  }
}

async function syncLobbyCompleted(lobby) {
  if (!isEnabled()) return;
  try {
    await db.collection('lobbies').doc(lobby.id).update({
      status: 'completed',
      raceId: lobby.raceId || null,
      completedAt: new Date().toISOString()
    });
    console.log(`Firestore: lobby ${lobby.id} completed`);
  } catch (error) {
    console.error(`Firestore: failed to sync lobby completed:`, error.message);
  }
}

// ============================================
// RACE SYNC
// ============================================

async function syncRaceCompleted(race) {
  if (!isEnabled()) return;
  try {
    // Write the race document
    const raceRef = db.collection('races').doc(race.id);
    await raceRef.set({
      id: race.id,
      lobbyId: race.lobbyId,
      targetDistance: race.targetDistance,
      status: race.status,
      startTime: race.startTime,
      completedAt: new Date().toISOString(),
      finishedCount: race.finishedCount
    });

    // Batch write results as subcollection
    const batch = db.batch();
    for (const p of race.participants) {
      const resultRef = raceRef.collection('results').doc(p.oderId);
      batch.set(resultRef, {
        oderId: p.oderId,
        displayName: p.displayName,
        walletAddress: p.walletAddress || '',
        equipmentType: p.equipmentType,
        position: p.position || null,
        finishTime: p.finishTime || null,
        distance: p.distance,
        pace: p.pace,
        watts: p.watts,
        isBot: p.isBot || false,
        isFinished: p.isFinished
      });
    }
    await batch.commit();
    console.log(`Firestore: race ${race.id} synced with ${race.participants.length} results`);
  } catch (error) {
    console.error(`Firestore: failed to sync race completed:`, error.message);
  }
}

// ============================================
// USER STATS
// ============================================

async function updateUserStats(race) {
  if (!isEnabled()) return;
  try {
    for (const p of race.participants) {
      if (p.isBot) continue; // Skip bots

      const userRef = db.collection('users').doc(p.oderId);
      const updateData = {
        totalRaces: admin.firestore.FieldValue.increment(1),
        lastActive: new Date().toISOString()
      };

      if (p.position === 1) {
        updateData.totalWins = admin.firestore.FieldValue.increment(1);
      }

      await userRef.set(updateData, { merge: true });
      console.log(`Firestore: user ${p.oderId} stats updated (position=${p.position})`);
    }
  } catch (error) {
    console.error(`Firestore: failed to update user stats:`, error.message);
  }
}

// ============================================
// USER PROFILE
// ============================================

async function saveUserProfile(userId, profileData) {
  if (!isEnabled()) return null;
  try {
    const userRef = db.collection('users').doc(userId);
    const data = {
      id: userId,
      displayName: profileData.displayName || 'Rower',
      lastActive: new Date().toISOString()
    };

    if (profileData.email) data.email = profileData.email;
    if (profileData.walletAddress) data.walletAddress = profileData.walletAddress;

    // Set defaults for new users, merge for existing
    await userRef.set({
      skillRating: 1500,
      totalRaces: 0,
      totalWins: 0,
      totalEarnings: '0',
      createdAt: new Date().toISOString(),
      ...data
    }, { merge: true });

    const doc = await userRef.get();
    console.log(`Firestore: user profile ${userId} saved`);
    return doc.data();
  } catch (error) {
    console.error(`Firestore: failed to save user profile:`, error.message);
    return null;
  }
}

async function getUserProfile(userId) {
  if (!isEnabled()) return null;
  try {
    const doc = await db.collection('users').doc(userId).get();
    if (!doc.exists) {
      console.log(`Firestore: user profile ${userId} not found`);
      return null;
    }
    console.log(`Firestore: user profile ${userId} fetched`);
    return doc.data();
  } catch (error) {
    console.error(`Firestore: failed to get user profile:`, error.message);
    return null;
  }
}

// ============================================
// LOBBY RECOVERY
// ============================================

async function loadWaitingLobbies() {
  if (!isEnabled()) return [];
  try {
    const snapshot = await db.collection('lobbies')
      .where('status', '==', 'waiting')
      .get();

    const lobbies = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      lobbies.push({
        id: data.id,
        creatorId: data.creatorId,
        raceDistance: data.raceDistance,
        entryFee: data.entryFee || '0',
        payoutMode: data.payoutMode || 'winner_takes_all',
        status: 'waiting',
        maxParticipants: data.maxParticipants || 10,
        minParticipants: data.minParticipants || 2,
        createdAt: data.createdAt,
        participants: [] // Socket.IO connections are lost on restart
      });
    });

    console.log(`Firestore: recovered ${lobbies.length} waiting lobbies`);
    return lobbies;
  } catch (error) {
    console.error(`Firestore: failed to load waiting lobbies:`, error.message);
    return [];
  }
}

module.exports = {
  syncLobbyCreated,
  syncLobbyStatusUpdate,
  syncLobbyCompleted,
  syncRaceCompleted,
  updateUserStats,
  saveUserProfile,
  getUserProfile,
  loadWaitingLobbies
};
