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


flutter: INFO: 2026-01-18 10:01:42.539989: service: 1826 <==> 2ad1
2026-01-18 10:01:44.407 ergpm_diagnostics[91138:16239653] [FBP-iOS] handleMethodCall: stopScan
flutter: INFO: 2026-01-18 10:01:55.421232: sending csafe command: f18686f2
flutter: INFO: 2026-01-18 10:01:55.574135: sending csafe command: f18787f2
flutter: INFO: 2026-01-18 10:01:55.753547: sending csafe command: f1210301002201f2
flutter: INFO: 2026-01-18 10:01:55.936908: sending csafe command: f11a0705058064000000f9f2
flutter: INFO: 2026-01-18 10:01:56.112869: sending csafe command: f12402000026f2c9a66
flutter: INFO: 2026-01-18 10:01:56.295543: sending csafe command: f18585f2



0xfe69e8fa8b2f54193a0c2e99e7bdd886a7be1141



⏺ Based on my exploration, this codebase has extensive Ethereum integration for race-based prize distribution. Here's how it works:                                                      
                                                                                                                                                                                         
  Smart Contract: RaceEscrow.sol                                                                                                                                                         
                                                                                                                                                                                         
  The core blockchain logic is in Contracts/RaceEscrow.sol. It's an escrow system using USDC (not raw ETH) for stability:                                                                
                                                                                                                                                                                         
  - Prize Distribution: Called via distributePrizes() after race completion                                                                                                              
  - Payout Modes:                                                                                                                                                                        
    - WINNER_TAKES_ALL - 1st place gets entire pool                                                                                                                                      
    - TOP_THREE - 60% / 30% / 10% split                                                                                                                                                  
  - Platform Fee: 5% deducted from prize pools                                                                                                                                           
                                                                                                                                                                                         
  iOS Wallet Integration                                                                                                                                                                 
                                                                                                                                                                                         
  WalletService.swift handles Ethereum interactions:                                                                                                                                     
  - WalletConnect integration (using ReownAppKit)                                                                                                                                        
  - Configured for Sepolia testnet (chain ID 11155111)                                                                                                                                   
  - Methods: depositToEscrow(), refreshBalance(), fetchETHBalance()                                                                                                                      
  - Transaction building with buildDepositCallData()                                                                                                                                     
                                                                                                                                                                                         
  Race Result & Payout Tracking                                                                                                                                                          
                                                                                                                                                                                         
  Race.swift defines:                                                                                                                                                                    
  struct RaceResult {                                                                                                                                                                    
      let payout: String       // Prize in wei                                                                                                                                           
      let walletAddress: String                                                                                                                                                          
      var payoutETH: Double    // Computed conversion                                                                                                                                    
  }                                                                                                                                                                                      
                                                                                                                                                                                         
  Lobby.swift tracks:                                                                                                                                                                    
  - entryFee (stored as wei string)                                                                                                                                                      
  - escrowTxHash - contract transaction reference                                                                                                                                        
  - prizePoolETH - calculated after 5% fee                                                                                                                                               
                                                                                                                                                                                         
  UserProfile.swift tracks:                                                                                                                                                              
  - walletAddress - linked Ethereum address                                                                                                                                              
  - totalEarnings - cumulative winnings in wei                                                                                                                                           
                                                                                                                                                                                         
  Current State                                                                                                                                                                          
                                                                                                                                                                                         
  The implementation is partially complete:                                                                                                                                              
  1. Smart contract is fully written with security patterns (ReentrancyGuard, Pausable)                                                                                                  
  2. UI for wallet management exists in WalletView.swift                                                                                                                                 
  3. WalletConnect connection flow is stubbed but not fully wired up                                                                                                                     
  4. Transaction signing logic is commented out pending full integration                                                                                                                 
                                                                                                                                                                                         
  The flow after race completion would be: race results → distributePrizes() called on contract → winners receive USDC to their linked wallet addresses → payoutTxHash stored for        
  reference.   