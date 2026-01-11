# PM5 Racing Server

Real-time multiplayer racing server for PM5 Racing iOS app.

## Quick Start

```bash
# Install dependencies
npm install

# Start server
npm start

# For development with auto-reload
npm run dev
```

Server runs on port 3000 by default.

## Making it Internet Accessible

### Option 1: ngrok (Quick testing)
```bash
# Install ngrok
brew install ngrok

# Expose your local server
ngrok http 3000
```
Use the provided HTTPS URL in your iOS app.

### Option 2: Deploy to Railway (Recommended for production)
1. Push code to GitHub
2. Go to [railway.app](https://railway.app)
3. Create new project from GitHub repo
4. Deploy - you'll get a public URL

### Option 3: Deploy to Render
1. Push code to GitHub
2. Go to [render.com](https://render.com)
3. Create new Web Service
4. Connect your repo
5. Deploy

### Option 4: Deploy to Fly.io
```bash
# Install flyctl
brew install flyctl

# Login and deploy
fly auth login
fly launch
fly deploy
```

## API Endpoints

### REST
- `GET /` - Server status
- `GET /lobbies` - List all waiting lobbies
- `GET /lobby/:id` - Get specific lobby

### Socket.IO Events

#### Client -> Server
| Event | Data | Description |
|-------|------|-------------|
| `createLobby` | `{creatorId, raceDistance, entryFee, payoutMode, maxParticipants}` | Create new lobby |
| `getLobbies` | - | Request lobby list |
| `joinLobby` | `{lobbyId, participant}` | Join a lobby |
| `addBot` | `{lobbyId, difficulty}` | Add bot (easy/medium/hard/elite) |
| `setReady` | `{lobbyId, oderId}` | Mark self as ready |
| `leaveLobby` | `{lobbyId, oderId}` | Leave lobby |
| `startRace` | `{lobbyId}` | Start the race |
| `raceUpdate` | `{raceId, oderId, metrics}` | Send race metrics |

#### Server -> Client
| Event | Data | Description |
|-------|------|-------------|
| `lobbyList` | `[Lobby]` | Updated lobby list |
| `lobbyCreated` | `Lobby` | Lobby creation confirmed |
| `lobbyUpdated` | `Lobby` | Lobby state changed |
| `countdown` | `number` | Countdown seconds (5,4,3,2,1) |
| `raceStarted` | `Race` | Race has begun |
| `raceUpdate` | `Race` | Race state update |
| `raceCompleted` | `Race` | Race finished |

## Bot Difficulties

| Difficulty | Pace (/500m) | Watts | Speed (m/s) |
|------------|--------------|-------|-------------|
| Easy | 2:30 | ~120W | 3.3 |
| Medium | 2:00 | ~180W | 4.2 |
| Hard | 1:40 | ~250W | 5.0 |
| Elite | 1:30 | ~320W | 5.6 |

## Environment Variables

- `PORT` - Server port (default: 3000)

ngrok config add-authtoken 301DbsQq2EhNuNEMOtqjUZUfWew_38F3sU5xoPp5TEQ8ZP7T5