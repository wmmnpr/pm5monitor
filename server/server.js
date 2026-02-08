const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const firestore = require('./firestoreSync');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// ============================================
// DATA STRUCTURES
// ============================================

// All active lobbies
const lobbies = new Map();

// All active races
const races = new Map();

// Bot configurations by difficulty
const BOT_CONFIGS = {
  easy: {
    avgPace: 150,      // 2:30/500m pace in seconds
    paceVariance: 10,
    avgWatts: 120,
    wattsVariance: 20,
    speedMetersPerSec: 3.3  // ~2:30 pace
  },
  medium: {
    avgPace: 120,      // 2:00/500m pace
    paceVariance: 8,
    avgWatts: 180,
    wattsVariance: 25,
    speedMetersPerSec: 4.2  // ~2:00 pace
  },
  hard: {
    avgPace: 100,      // 1:40/500m pace
    paceVariance: 5,
    avgWatts: 250,
    wattsVariance: 30,
    speedMetersPerSec: 5.0  // ~1:40 pace
  },
  elite: {
    avgPace: 90,       // 1:30/500m pace
    paceVariance: 3,
    avgWatts: 320,
    wattsVariance: 35,
    speedMetersPerSec: 5.6  // ~1:30 pace
  }
};

const BOT_NAMES = [
  'RoboRower', 'CyberSki', 'BikeBotX', 'IronPull', 'SteelStroke',
  'TurboErg', 'MechRacer', 'AlphaBot', 'BetaRow', 'GammaGlide',
  'DeltaDrive', 'EpsilonErg', 'ZetaZoom', 'ThetaThrust', 'OmegaOar'
];

// Configurable wallet address for bots (for testing tip functionality)
// Set this to your own wallet address to receive test tips from bots
const BOT_WALLET_ADDRESS = "0x985d1755e5b1bfda8168f7b89e7758e49d365b47";

// ============================================
// LOBBY MANAGEMENT
// ============================================

function createLobby(data) {
  const lobbyId = uuidv4();
  const lobby = {
    id: lobbyId,
    creatorId: data.creatorId,
    raceDistance: data.raceDistance,
    entryFee: data.entryFee || "0",
    payoutMode: data.payoutMode || "winner_takes_all",
    status: "waiting",
    maxParticipants: data.maxParticipants || 10,
    minParticipants: data.minParticipants || 2,
    createdAt: new Date().toISOString(),
    participants: []
  };
  lobbies.set(lobbyId, lobby);
  return lobby;
}

function getLobbyList() {
  return Array.from(lobbies.values())
    .filter(l => l.status === 'waiting' || l.status === 'completed')
    .map(l => ({
      ...l,
      participantCount: l.participants.length
    }));
}

function getLobbyListForUser(userId) {
  return Array.from(lobbies.values())
    .filter(l => {
      if (l.status !== 'waiting' && l.status !== 'completed') return false;
      // Show lobby if user is the creator or a participant
      if (l.creatorId === userId) return true;
      if (l.participants.some(p => p.id === userId || p.oderId === userId)) return true;
      return false;
    })
    .map(l => ({
      ...l,
      participantCount: l.participants.length
    }));
}

// Send filtered lobby lists to all connected sockets
function broadcastLobbyLists() {
  for (const [, s] of io.sockets.sockets) {
    const userId = s.userId;
    if (userId) {
      s.emit('lobbyList', getLobbyListForUser(userId));
    } else {
      // No userId identified yet — send empty list
      s.emit('lobbyList', []);
    }
  }
}

function completeRace(lobbyId, race) {
  const lobby = lobbies.get(lobbyId);
  if (lobby) {
    lobby.status = 'completed';
    lobby.raceId = race.id;
    lobby.raceResults = race.participants.map(p => ({
      oderId: p.oderId,
      displayName: p.displayName,
      walletAddress: p.walletAddress || "",
      position: p.position,
      finishTime: p.finishTime,
      distance: p.distance,
      pace: p.pace,
      watts: p.watts,
      isBot: p.isBot,
      isFinished: p.isFinished
    }));
  }
  return lobby;
}

function addParticipant(lobbyId, participant) {
  const lobby = lobbies.get(lobbyId);
  if (!lobby) return null;
  if (lobby.participants.length >= lobby.maxParticipants) return null;

  // Check if already joined
  if (lobby.participants.find(p => p.id === participant.id)) {
    return lobby;
  }

  lobby.participants.push({
    id: participant.id,
    oderId: participant.oderId,
    displayName: participant.displayName,
    walletAddress: participant.walletAddress || "",
    equipmentType: participant.equipmentType || "rower",
    status: "deposited",
    isBot: participant.isBot || false,
    botDifficulty: participant.botDifficulty || null,
    joinedAt: new Date().toISOString()
  });

  return lobby;
}

function addBot(lobbyId, difficulty) {
  const lobby = lobbies.get(lobbyId);
  if (!lobby) return null;
  if (lobby.participants.length >= lobby.maxParticipants) return null;

  const botId = `bot-${uuidv4().slice(0, 8)}`;
  const botName = BOT_NAMES[Math.floor(Math.random() * BOT_NAMES.length)];
  const equipmentTypes = ['rower', 'bike', 'ski'];
  const randomEquipment = equipmentTypes[Math.floor(Math.random() * equipmentTypes.length)];

  const bot = {
    id: botId,
    oderId: botId,
    displayName: `${botName} (${difficulty})`,
    walletAddress: BOT_WALLET_ADDRESS,
    equipmentType: randomEquipment,
    status: "ready",
    isBot: true,
    botDifficulty: difficulty,
    joinedAt: new Date().toISOString()
  };

  lobby.participants.push(bot);
  return { lobby, bot };
}

function setParticipantReady(lobbyId, oderId) {
  const lobby = lobbies.get(lobbyId);
  if (!lobby) return null;

  const participant = lobby.participants.find(p => p.oderId === oderId);
  if (participant) {
    participant.status = "ready";
  }

  return lobby;
}

function removeParticipant(lobbyId, oderId) {
  const lobby = lobbies.get(lobbyId);
  if (!lobby) return null;

  lobby.participants = lobby.participants.filter(p => p.oderId !== oderId);
  return lobby;
}

// ============================================
// RACE MANAGEMENT
// ============================================

function startRace(lobbyId) {
  const lobby = lobbies.get(lobbyId);
  if (!lobby) return null;

  // Check all participants are ready
  const allReady = lobby.participants.every(p => p.status === 'ready' || p.isBot);
  if (!allReady) return null;

  lobby.status = 'in_progress';

  const raceId = uuidv4();
  const race = {
    id: raceId,
    lobbyId: lobbyId,
    status: 'active',
    startTime: null,
    targetDistance: lobby.raceDistance,
    participants: lobby.participants.map(p => ({
      id: p.id,
      oderId: p.oderId,
      displayName: p.displayName,
      walletAddress: p.walletAddress || "",
      equipmentType: p.equipmentType,
      isBot: p.isBot,
      botDifficulty: p.botDifficulty,
      distance: 0,
      pace: 0,
      watts: 0,
      isFinished: false,
      finishTime: null,
      position: null
    })),
    finishedCount: 0
  };

  races.set(raceId, race);
  return race;
}

function updateRaceParticipant(raceId, oderId, metrics) {
  const race = races.get(raceId);
  if (!race) return null;

  const participant = race.participants.find(p => p.oderId === oderId);
  if (!participant || participant.isFinished) return race;

  participant.distance = metrics.distance;
  participant.pace = metrics.pace;
  participant.watts = metrics.watts;

  // Check if finished
  if (participant.distance >= race.targetDistance && !participant.isFinished) {
    participant.isFinished = true;
    participant.finishTime = Date.now() - race.startTime;
    race.finishedCount++;
    participant.position = race.finishedCount;
  }

  return race;
}

function simulateBots(race) {
  if (!race || race.status !== 'racing') return;

  const elapsedMs = Date.now() - race.startTime;
  const elapsedSec = elapsedMs / 1000;

  race.participants.forEach(p => {
    if (!p.isBot || p.isFinished) return;

    const config = BOT_CONFIGS[p.botDifficulty] || BOT_CONFIGS.medium;

    // Add some variance to make it realistic
    const variance = (Math.random() - 0.5) * 0.2;
    const speed = config.speedMetersPerSec * (1 + variance);

    // Ensure distance never decreases (variance could otherwise cause backwards movement)
    const newDistance = Math.min(elapsedSec * speed, race.targetDistance);
    p.distance = Math.max(p.distance, newDistance);
    p.pace = config.avgPace + (Math.random() - 0.5) * config.paceVariance;
    p.watts = Math.round(config.avgWatts + (Math.random() - 0.5) * config.wattsVariance);

    // Check if bot finished
    if (p.distance >= race.targetDistance && !p.isFinished) {
      p.isFinished = true;
      p.finishTime = elapsedMs;
      race.finishedCount++;
      p.position = race.finishedCount;
    }
  });

  return race;
}

// ============================================
// SOCKET.IO HANDLERS
// ============================================

io.on('connection', (socket) => {
  console.log(`io Client connected: ${socket.id}`);

  // Client identifies itself with userId
  socket.on('identify', (data) => {
    const userId = data.userId;
    if (userId) {
      socket.userId = userId;
      console.log(`Socket ${socket.id} identified as user ${userId}`);
      // Send filtered lobby list now that we know who they are
      socket.emit('lobbyList', getLobbyListForUser(userId));
    }
  });

  // ---- LOBBY EVENTS ----

  socket.on('createLobby', (data) => {
    console.log(`socket createLobby`);
    const lobby = createLobby(data);
    socket.join(`lobby:${lobby.id}`);
    broadcastLobbyLists();
    socket.emit('lobbyCreated', lobby);
    firestore.syncLobbyCreated(lobby);
    console.log(`Lobby created: ${lobby.id}`);
  });

  socket.on('getLobbies', (data) => {
    console.log("socket getLobbies");
    const userId = (data && data.userId) || socket.userId;
    if (userId) {
      socket.emit('lobbyList', getLobbyListForUser(userId));
    } else {
      socket.emit('lobbyList', []);
    }
  });

  socket.on('joinLobby', (data) => {
    console.log("socket joinLobby");
    const { lobbyId, participant } = data;
    const lobby = addParticipant(lobbyId, participant);
    if (lobby) {
      socket.join(`lobby:${lobbyId}`);
      io.to(`lobby:${lobbyId}`).emit('lobbyUpdated', lobby);
      broadcastLobbyLists();
      firestore.syncLobbyStatusUpdate(lobbyId, lobby.status, lobby.participants.length);
      console.log(`${participant.displayName} joined lobby ${lobbyId}`);
    }
  });

  socket.on('addBot', (data) => {
    console.log("socket addBot");
    const { lobbyId, difficulty } = data;
    const result = addBot(lobbyId, difficulty);
    if (result) {
      io.to(`lobby:${lobbyId}`).emit('lobbyUpdated', result.lobby);
      broadcastLobbyLists();
      firestore.syncLobbyStatusUpdate(lobbyId, result.lobby.status, result.lobby.participants.length);
      console.log(`Bot added to lobby ${lobbyId} with difficulty ${difficulty}`);
    }
  });

  socket.on('setReady', (data) => {
    console.log("socket setReady");
    const { lobbyId, oderId } = data;
    const lobby = setParticipantReady(lobbyId, oderId);
    if (lobby) {
      io.to(`lobby:${lobbyId}`).emit('lobbyUpdated', lobby);
    }
  });

  socket.on('leaveLobby', (data) => {
    console.log("socket leaveLobby");
    const { lobbyId, oderId } = data;
    const lobby = removeParticipant(lobbyId, oderId);
    if (lobby) {
      socket.leave(`lobby:${lobbyId}`);
      io.to(`lobby:${lobbyId}`).emit('lobbyUpdated', lobby);
      broadcastLobbyLists();
      firestore.syncLobbyStatusUpdate(lobbyId, lobby.status, lobby.participants.length);
    }
  });

  // Rejoin lobby room (for reconnection or after REST join)
  socket.on('rejoinLobby', (data) => {
    const { lobbyId } = data;
    const lobby = lobbies.get(lobbyId);
    if (lobby) {
      socket.join(`lobby:${lobbyId}`);
      console.log(`Socket ${socket.id} rejoined lobby room ${lobbyId}`);
      // Send current lobby state to the rejoining client
      socket.emit('lobbyUpdated', lobby);
      // If there's an active race, send current race state
      const race = Array.from(races.values()).find(r => r.lobbyId === lobbyId && r.status === 'racing');
      if (race) {
        socket.emit('raceUpdate', race);
      }
    }
  });

  // ---- RACE EVENTS ----

  socket.on('startRace', (data) => {
    const { lobbyId } = data;
    const race = startRace(lobbyId);
    if (race) {
      firestore.syncLobbyStatusUpdate(lobbyId, 'in_progress', race.participants.length);

      // 5 second countdown
      let countdown = 5;
      const countdownInterval = setInterval(() => {
        io.to(`lobby:${lobbyId}`).emit('countdown', countdown);
        countdown--;
        if (countdown < 0) {
          clearInterval(countdownInterval);
          race.startTime = Date.now();
          race.status = 'racing';
          io.to(`lobby:${lobbyId}`).emit('raceStarted', race);

          // Start bot simulation loop
          const botInterval = setInterval(() => {
            if (race.status !== 'racing') {
              clearInterval(botInterval);
              return;
            }

            simulateBots(race);
            io.to(`lobby:${lobbyId}`).emit('raceUpdate', race);

            // Check if race is complete
            const allFinished = race.participants.every(p => p.isFinished);
            if (allFinished) {
              race.status = 'completed';
              clearInterval(botInterval);
              const completedLobby = completeRace(lobbyId, race);
              io.to(`lobby:${lobbyId}`).emit('raceCompleted', race);
              broadcastLobbyLists();

              if (!race.firestoreSynced) {
                race.firestoreSynced = true;
                firestore.syncRaceCompleted(race);
                if (completedLobby) firestore.syncLobbyCompleted(completedLobby);
                firestore.updateUserStats(race);
              }
            }
          }, 500); // Update every 500ms
        }
      }, 1000);

      console.log(`Race started for lobby ${lobbyId}`);
    }
  });

  socket.on('raceUpdate', (data) => {
    const { raceId, oderId, metrics } = data;
    const race = updateRaceParticipant(raceId, oderId, metrics);
    if (race) {
      io.to(`lobby:${race.lobbyId}`).emit('raceUpdate', race);

      // Check if race complete
      const allFinished = race.participants.every(p => p.isFinished);
      if (allFinished && race.status === 'racing') {
        race.status = 'completed';
        const completedLobby = completeRace(race.lobbyId, race);
        io.to(`lobby:${race.lobbyId}`).emit('raceCompleted', race);
        broadcastLobbyLists();

        if (!race.firestoreSynced) {
          race.firestoreSynced = true;
          firestore.syncRaceCompleted(race);
          if (completedLobby) firestore.syncLobbyCompleted(completedLobby);
          firestore.updateUserStats(race);
        }
      }
    }
  });

  socket.on('disconnect', () => {
    console.log(`Client disconnected: ${socket.id}`);
  });
});

// ============================================
// REST ENDPOINTS
// ============================================

app.get('/', (req, res) => {
  res.json({
    name: 'rest PM5 Racing Server',
    version: '1.0.0',
    status: 'running',
    lobbies: lobbies.size,
    races: races.size
  });
});

app.get('/lobbies', (req, res) => {
  console.log("rest GET /lobbies called");
  const userId = req.query.userId;
  if (userId) {
    res.json(getLobbyListForUser(userId));
  } else {
    res.json([]);
  }
});

app.get('/lobby/:id', (req, res) => {
  const lobby = lobbies.get(req.params.id);
  console.log(`GET /lobbies/${lobby} called`);
  if (lobby) {
    res.json(lobby);
  } else {
    res.status(404).json({ error: 'Lobby not found' });
  }
});

// Create lobby
app.post('/api/lobby', (req, res) => {
  console.log(`POST /api/lobby called`);
  const lobby = createLobby(req.body);
  broadcastLobbyLists();
  firestore.syncLobbyCreated(lobby);
  res.json(lobby);
});

// Join lobby
app.post('/api/lobby/:id/join', (req, res) => {
  console.log(`POST /api/lobby/${req.params.id}/join called`);
  const lobby = addParticipant(req.params.id, req.body);
  if (lobby) {
    io.to(`lobby:${req.params.id}`).emit('lobbyUpdated', lobby);
    broadcastLobbyLists();
    firestore.syncLobbyStatusUpdate(req.params.id, lobby.status, lobby.participants.length);
    res.json(lobby);
  } else {
    res.status(400).json({ error: 'Cannot join lobby' });
  }
});

// Add bot
app.post('/api/lobby/:id/bot', (req, res) => {
  console.log(`POST /api/lobby/${req.params.id}/bot called`);
  const result = addBot(req.params.id, req.body.difficulty || 'medium');
  if (result) {
    io.to(`lobby:${req.params.id}`).emit('lobbyUpdated', result.lobby);
    broadcastLobbyLists();
    firestore.syncLobbyStatusUpdate(req.params.id, result.lobby.status, result.lobby.participants.length);
    res.json(result.lobby);
  } else {
    res.status(400).json({ error: 'Cannot add bot' });
  }
});

// Set ready
app.post('/api/lobby/:id/ready', (req, res) => {
  console.log(`POST /api/lobby/${req.params.id}/ready called`);
  const lobby = setParticipantReady(req.params.id, req.body.oderId);
  if (lobby) {
    io.to(`lobby:${req.params.id}`).emit('lobbyUpdated', lobby);
    res.json(lobby);
  } else {
    res.status(400).json({ error: 'Cannot set ready' });
  }
});

// Start race
app.post('/api/lobby/:id/start', (req, res) => {
  console.log(`POST /api/lobby/${req.params.id}/start called`);
  const lobbyId = req.params.id;
  const race = startRace(lobbyId);
  if (race) {
    firestore.syncLobbyStatusUpdate(lobbyId, 'in_progress', race.participants.length);

    // Start countdown
    let countdown = 5;
    const countdownInterval = setInterval(() => {
      io.to(`lobby:${lobbyId}`).emit('countdown', countdown);
      countdown--;
      if (countdown < 0) {
        clearInterval(countdownInterval);
        race.startTime = Date.now();
        race.status = 'racing';
        io.to(`lobby:${lobbyId}`).emit('raceStarted', race);

        // Start bot simulation
        const botInterval = setInterval(() => {
          if (race.status !== 'racing') {
            clearInterval(botInterval);
            return;
          }
          simulateBots(race);
          io.to(`lobby:${lobbyId}`).emit('raceUpdate', race);

          const allFinished = race.participants.every(p => p.isFinished);
          if (allFinished) {
            race.status = 'completed';
            clearInterval(botInterval);
            const completedLobby = completeRace(lobbyId, race);
            io.to(`lobby:${lobbyId}`).emit('raceCompleted', race);
            broadcastLobbyLists();

            if (!race.firestoreSynced) {
              race.firestoreSynced = true;
              firestore.syncRaceCompleted(race);
              if (completedLobby) firestore.syncLobbyCompleted(completedLobby);
              firestore.updateUserStats(race);
            }
          }
        }, 500);
      }
    }, 1000);

    res.json(race);
  } else {
    res.status(400).json({ error: 'Cannot start race' });
  }
});

// Race update
app.post('/api/race/:id/update', (req, res) => {
  const { oderId, distance, pace, watts } = req.body;
  const race = updateRaceParticipant(req.params.id, oderId, { distance, pace, watts });
  if (race) {
    io.to(`lobby:${race.lobbyId}`).emit('raceUpdate', race);

    const allFinished = race.participants.every(p => p.isFinished);
    if (allFinished && race.status === 'racing') {
      race.status = 'completed';
      const completedLobby = completeRace(race.lobbyId, race);
      io.to(`lobby:${race.lobbyId}`).emit('raceCompleted', race);
      broadcastLobbyLists();

      if (!race.firestoreSynced) {
        race.firestoreSynced = true;
        firestore.syncRaceCompleted(race);
        if (completedLobby) firestore.syncLobbyCompleted(completedLobby);
        firestore.updateUserStats(race);
      }
    }

    res.json(race);
  } else {
    res.status(400).json({ error: 'Race not found' });
  }
});

// Get race
app.get('/api/race/:id', (req, res) => {
  const race = races.get(req.params.id);
  if (race) {
    res.json(race);
  } else {
    res.status(404).json({ error: 'Race not found' });
  }
});

// Get user profile
app.get('/api/user/:id/profile', async (req, res) => {
  console.log(`GET /api/user/${req.params.id}/profile called`);
  const profile = await firestore.getUserProfile(req.params.id);
  if (profile) {
    res.json(profile);
  } else {
    res.status(404).json({ error: 'User profile not found' });
  }
});

// Save user profile
app.post('/api/user/:id/profile', async (req, res) => {
  console.log(`POST /api/user/${req.params.id}/profile called`);
  const profile = await firestore.saveUserProfile(req.params.id, req.body);
  if (profile) {
    res.json(profile);
  } else {
    res.status(500).json({ error: 'Failed to save user profile' });
  }
});

// ============================================
// START SERVER
// ============================================

// Recover waiting lobbies from Firestore on startup
firestore.loadWaitingLobbies().then(recoveredLobbies => {
  for (const lobby of recoveredLobbies) {
    if (!lobbies.has(lobby.id)) {
      lobbies.set(lobby.id, lobby);
    }
  }
  if (recoveredLobbies.length > 0) {
    console.log(`Recovered ${recoveredLobbies.length} lobbies from Firestore`);
  }
}).catch(err => {
  console.error('Lobby recovery failed:', err.message);
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔═══════════════════════════════════════════════════════╗
║           PM5 Racing Server v1.0.0                   ║
╠═══════════════════════════════════════════════════════╣
║  HTTP:   http://localhost:${PORT}                        ║
║  Socket: ws://localhost:${PORT}                          ║
║                                                       ║
║  For external access, use ngrok or deploy to cloud   ║
╚═══════════════════════════════════════════════════════╝
  `);
});
