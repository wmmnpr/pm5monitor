const { io } = require("socket.io-client");

//const socket = io("http://localhost:3000");
const socket = io("https://bc1f33e92fa6.ngrok-free.app");


let currentLobbyId = null;
const oderId = "test-oder-" + Date.now();

socket.on("connect", () => {
  console.log("Connected with id:", socket.id);
  console.log("\nCommands:");
  console.log("  list        - Get lobby list");
  console.log("  create      - Create a lobby");
  console.log("  join <id>   - Join a lobby");
  console.log("  bot <diff>  - Add bot (easy/medium/hard/elite)");
  console.log("  ready       - Set ready");
  console.log("  start       - Start race");
  console.log("  quit        - Exit\n");
});

socket.on("disconnect", () => {
  console.log("Disconnected");
});

socket.on("lobbyList", (lobbies) => {
  console.log("\nLobbies:", JSON.stringify(lobbies, null, 2));
});

socket.on("lobbyCreated", (lobby) => {
  currentLobbyId = lobby.id;
  console.log("\nLobby created:", lobby.id);
});

socket.on("lobbyUpdated", (lobby) => {
  console.log("\nLobby updated:", JSON.stringify(lobby, null, 2));
});

socket.on("countdown", (count) => {
  console.log("Countdown:", count);
});

socket.on("raceStarted", (race) => {
  console.log("\nRace started!", race.id);
});

socket.on("raceUpdate", (race) => {
  const positions = race.participants
    .sort((a, b) => b.distance - a.distance)
    .map((p, i) => `${i + 1}. ${p.displayName}: ${p.distance.toFixed(1)}m`)
    .join(" | ");
  process.stdout.write(`\r${positions}          `);
});

socket.on("raceCompleted", (race) => {
  console.log("\n\nRace completed!");
  race.participants
    .sort((a, b) => a.position - b.position)
    .forEach((p) => {
      console.log(`  ${p.position}. ${p.displayName} - ${(p.finishTime / 1000).toFixed(1)}s`);
    });
});

// Handle stdin for commands
const readline = require("readline");
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

rl.on("line", (line) => {
  const [cmd, ...args] = line.trim().split(" ");

  switch (cmd) {
    case "list":
      socket.emit("getLobbies");
      break;

    case "create":
      socket.emit("createLobby", {
        creatorId: oderId,
        raceDistance: 500,
        entryFee: "0",
        payoutMode: "winner_takes_all",
        maxParticipants: 10,
      });
      break;

    case "join":
      currentLobbyId = args[0] || currentLobbyId;
      if (!currentLobbyId) {
        console.log("No lobby ID. Create one first or specify: join <id>");
        break;
      }
      socket.emit("joinLobby", {
        lobbyId: currentLobbyId,
        participant: {
          id: oderId,
          oderId: oderId,
          displayName: "TestRower",
          walletAddress: "0x123",
          equipmentType: "rower",
        },
      });
      break;

    case "bot":
      if (!currentLobbyId) {
        console.log("No lobby. Create or join one first.");
        break;
      }
      socket.emit("addBot", {
        lobbyId: currentLobbyId,
        difficulty: args[0] || "medium",
      });
      break;

    case "ready":
      if (!currentLobbyId) {
        console.log("No lobby. Create or join one first.");
        break;
      }
      socket.emit("setReady", {
        lobbyId: currentLobbyId,
        oderId: oderId,
      });
      break;

    case "start":
      if (!currentLobbyId) {
        console.log("No lobby. Create or join one first.");
        break;
      }
      socket.emit("startRace", { lobbyId: currentLobbyId });
      break;

    case "quit":
      socket.disconnect();
      process.exit(0);
      break;

    default:
      console.log("Unknown command:", cmd);
  }
});

rl.on("close", () => {
  socket.disconnect();
  process.exit(0);
});
