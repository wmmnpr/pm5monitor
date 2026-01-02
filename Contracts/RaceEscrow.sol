// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RaceEscrow
 * @notice Escrow contract for PM5 Racing - holds entry fees and distributes prizes
 * @dev Uses USDC (6 decimals) for all transactions
 *
 * DEPLOYMENT INSTRUCTIONS:
 * 1. Install dependencies: npm install @openzeppelin/contracts
 * 2. Compile: npx hardhat compile
 * 3. Deploy to testnet first (Sepolia):
 *    - USDC on Sepolia: Deploy a mock ERC20 or use existing test USDC
 * 4. After testing, deploy to mainnet:
 *    - USDC Mainnet: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
 * 5. Update escrowContractAddress in WalletService.swift
 */
contract RaceEscrow is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    IERC20 public immutable usdc;

    /// @notice Platform fee percentage (5% = 500 basis points)
    uint256 public platformFeePercent = 500; // 5%
    uint256 public constant MAX_FEE = 1000; // 10% max
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Accumulated platform fees available for withdrawal
    uint256 public accumulatedFees;

    /// @notice Payout modes
    uint8 public constant WINNER_TAKES_ALL = 0;
    uint8 public constant TOP_THREE = 1;

    /// @notice Race structure
    struct Race {
        bytes32 lobbyId;
        uint256 entryFee;
        uint256 totalPool;
        uint8 payoutMode;
        bool isActive;
        bool isPaidOut;
        address[] participants;
    }

    /// @notice Mapping from lobbyId to Race
    mapping(bytes32 => Race) public races;

    /// @notice Mapping from lobbyId to participant deposit status
    mapping(bytes32 => mapping(address => bool)) public hasDeposited;

    // ============================================
    // EVENTS
    // ============================================

    event RaceCreated(
        bytes32 indexed lobbyId,
        uint256 entryFee,
        uint8 payoutMode
    );

    event Deposited(
        bytes32 indexed lobbyId,
        address indexed participant,
        uint256 amount
    );

    event RaceCompleted(
        bytes32 indexed lobbyId,
        address[] winners,
        uint256[] payouts
    );

    event Refunded(
        bytes32 indexed lobbyId,
        address indexed participant,
        uint256 amount
    );

    event RaceCancelled(bytes32 indexed lobbyId);

    event FeesWithdrawn(address indexed to, uint256 amount);

    event FeePercentUpdated(uint256 oldFee, uint256 newFee);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize the escrow contract
     * @param _usdc Address of the USDC token contract
     */
    constructor(address _usdc) {
        require(_usdc != address(0), "Invalid USDC address");
        usdc = IERC20(_usdc);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Create a new race (admin only, called by backend)
     * @param lobbyId Unique identifier for the lobby (hashed from Firebase ID)
     * @param entryFee Entry fee in USDC (6 decimals)
     * @param payoutMode 0 = Winner takes all, 1 = Top 3
     */
    function createRace(
        bytes32 lobbyId,
        uint256 entryFee,
        uint8 payoutMode
    ) external onlyOwner whenNotPaused {
        require(!races[lobbyId].isActive, "Race already exists");
        require(entryFee > 0, "Entry fee must be > 0");
        require(payoutMode <= TOP_THREE, "Invalid payout mode");

        races[lobbyId] = Race({
            lobbyId: lobbyId,
            entryFee: entryFee,
            totalPool: 0,
            payoutMode: payoutMode,
            isActive: true,
            isPaidOut: false,
            participants: new address[](0)
        });

        emit RaceCreated(lobbyId, entryFee, payoutMode);
    }

    /**
     * @notice Distribute prizes to winners (admin only, called by backend)
     * @param lobbyId The race lobby ID
     * @param winners Array of winner addresses in order (1st, 2nd, 3rd)
     */
    function distributePrizes(
        bytes32 lobbyId,
        address[] calldata winners
    ) external onlyOwner nonReentrant whenNotPaused {
        Race storage race = races[lobbyId];
        require(race.isActive, "Race not active");
        require(!race.isPaidOut, "Already paid out");
        require(winners.length > 0, "No winners");

        // Calculate platform fee
        uint256 platformFee = (race.totalPool * platformFeePercent) / BASIS_POINTS;
        uint256 prizePool = race.totalPool - platformFee;

        // Accumulate platform fee
        accumulatedFees += platformFee;

        // Calculate and distribute payouts
        uint256[] memory payouts = calculatePayouts(race.payoutMode, prizePool, winners.length);

        for (uint256 i = 0; i < winners.length && i < payouts.length; i++) {
            if (payouts[i] > 0) {
                usdc.safeTransfer(winners[i], payouts[i]);
            }
        }

        race.isPaidOut = true;
        race.isActive = false;

        emit RaceCompleted(lobbyId, winners, payouts);
    }

    /**
     * @notice Cancel race and refund all participants (admin only)
     * @param lobbyId The race lobby ID
     */
    function cancelRace(bytes32 lobbyId) external onlyOwner nonReentrant {
        Race storage race = races[lobbyId];
        require(race.isActive, "Race not active");
        require(!race.isPaidOut, "Already paid out");

        // Refund all participants
        for (uint256 i = 0; i < race.participants.length; i++) {
            address participant = race.participants[i];
            if (hasDeposited[lobbyId][participant]) {
                usdc.safeTransfer(participant, race.entryFee);
                emit Refunded(lobbyId, participant, race.entryFee);
            }
        }

        race.isActive = false;
        emit RaceCancelled(lobbyId);
    }

    /**
     * @notice Withdraw accumulated platform fees
     * @param to Address to send fees to
     */
    function withdrawFees(address to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid address");
        require(accumulatedFees > 0, "No fees to withdraw");

        uint256 amount = accumulatedFees;
        accumulatedFees = 0;

        usdc.safeTransfer(to, amount);
        emit FeesWithdrawn(to, amount);
    }

    /**
     * @notice Update platform fee percentage
     * @param newFeePercent New fee in basis points (e.g., 500 = 5%)
     */
    function updateFeePercent(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= MAX_FEE, "Fee too high");

        uint256 oldFee = platformFeePercent;
        platformFeePercent = newFeePercent;

        emit FeePercentUpdated(oldFee, newFeePercent);
    }

    /**
     * @notice Pause the contract (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    // USER FUNCTIONS
    // ============================================

    /**
     * @notice Deposit entry fee to join a race
     * @param lobbyId The race lobby ID
     * @dev Requires prior USDC approval
     */
    function deposit(bytes32 lobbyId) external nonReentrant whenNotPaused {
        Race storage race = races[lobbyId];
        require(race.isActive, "Race not active");
        require(!hasDeposited[lobbyId][msg.sender], "Already deposited");

        // Transfer USDC from user
        usdc.safeTransferFrom(msg.sender, address(this), race.entryFee);

        // Record deposit
        race.participants.push(msg.sender);
        hasDeposited[lobbyId][msg.sender] = true;
        race.totalPool += race.entryFee;

        emit Deposited(lobbyId, msg.sender, race.entryFee);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get race details
     * @param lobbyId The race lobby ID
     */
    function getRace(bytes32 lobbyId) external view returns (
        uint256 entryFee,
        uint256 totalPool,
        uint8 payoutMode,
        bool isActive,
        bool isPaidOut,
        uint256 participantCount
    ) {
        Race storage race = races[lobbyId];
        return (
            race.entryFee,
            race.totalPool,
            race.payoutMode,
            race.isActive,
            race.isPaidOut,
            race.participants.length
        );
    }

    /**
     * @notice Get participants for a race
     * @param lobbyId The race lobby ID
     */
    function getParticipants(bytes32 lobbyId) external view returns (address[] memory) {
        return races[lobbyId].participants;
    }

    /**
     * @notice Check if address has deposited for a race
     * @param lobbyId The race lobby ID
     * @param participant The address to check
     */
    function hasParticipantDeposited(bytes32 lobbyId, address participant) external view returns (bool) {
        return hasDeposited[lobbyId][participant];
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Calculate payouts based on payout mode
     * @param payoutMode The payout distribution mode
     * @param prizePool Total prize pool after fees
     * @param winnerCount Number of winners
     */
    function calculatePayouts(
        uint8 payoutMode,
        uint256 prizePool,
        uint256 winnerCount
    ) internal pure returns (uint256[] memory) {
        uint256[] memory payouts;

        if (payoutMode == WINNER_TAKES_ALL) {
            payouts = new uint256[](1);
            payouts[0] = prizePool;
        } else if (payoutMode == TOP_THREE) {
            payouts = new uint256[](3);
            // 60% / 30% / 10%
            payouts[0] = (prizePool * 6000) / BASIS_POINTS;
            payouts[1] = (prizePool * 3000) / BASIS_POINTS;
            payouts[2] = (prizePool * 1000) / BASIS_POINTS;

            // Adjust if fewer winners
            if (winnerCount < 3) {
                // Redistribute 3rd place
                payouts[0] += payouts[2] / 2;
                payouts[1] += payouts[2] / 2;
                payouts[2] = 0;
            }
            if (winnerCount < 2) {
                // Give all to 1st
                payouts[0] += payouts[1];
                payouts[1] = 0;
            }
        }

        return payouts;
    }
}
