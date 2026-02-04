// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AgentEscrow
 * @notice USDC escrow for agent-to-agent service transactions
 * @dev Circle USDC Hackathon - Agentic Commerce Track
 * 
 * Flow:
 * 1. Buyer creates escrow, locking USDC
 * 2. Seller delivers service off-chain
 * 3. Buyer releases funds OR timeout triggers auto-release
 * 4. Disputes go to simple timeout-based resolution
 */
contract AgentEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    
    enum EscrowState { Active, Released, Refunded, Disputed }
    
    struct Escrow {
        address buyer;
        address seller;
        uint256 amount;
        uint256 createdAt;
        uint256 timeoutSeconds;
        EscrowState state;
        bytes32 serviceId; // Reference to off-chain service listing
    }
    
    mapping(uint256 => Escrow) public escrows;
    uint256 public escrowCount;
    
    // Agent reputation scores (simple on-chain tracking)
    mapping(address => uint256) public completedAsseller;
    mapping(address => uint256) public completedAsBuyer;
    
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        bytes32 serviceId
    );
    
    event EscrowReleased(uint256 indexed escrowId, address indexed seller, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowDisputed(uint256 indexed escrowId, address indexed disputer);
    
    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }
    
    /**
     * @notice Create a new escrow for a service purchase
     * @param seller Address of the service provider (agent)
     * @param amount USDC amount to escrow
     * @param timeoutSeconds Time after which seller can claim if buyer doesn't respond
     * @param serviceId Off-chain reference to the service being purchased
     */
    function createEscrow(
        address seller,
        uint256 amount,
        uint256 timeoutSeconds,
        bytes32 serviceId
    ) external nonReentrant returns (uint256 escrowId) {
        require(seller != address(0), "Invalid seller");
        require(seller != msg.sender, "Cannot escrow to yourself");
        require(amount > 0, "Amount must be positive");
        require(timeoutSeconds >= 1 hours, "Timeout too short");
        require(timeoutSeconds <= 30 days, "Timeout too long");
        
        escrowId = escrowCount++;
        
        escrows[escrowId] = Escrow({
            buyer: msg.sender,
            seller: seller,
            amount: amount,
            createdAt: block.timestamp,
            timeoutSeconds: timeoutSeconds,
            state: EscrowState.Active,
            serviceId: serviceId
        });
        
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        
        emit EscrowCreated(escrowId, msg.sender, seller, amount, serviceId);
    }
    
    /**
     * @notice Buyer releases funds to seller after service completion
     * @param escrowId The escrow to release
     */
    function release(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        require(e.state == EscrowState.Active, "Escrow not active");
        require(msg.sender == e.buyer, "Only buyer can release");
        
        e.state = EscrowState.Released;
        completedAsseller[e.seller]++;
        completedAsBuyer[e.buyer]++;
        
        usdc.safeTransfer(e.seller, e.amount);
        
        emit EscrowReleased(escrowId, e.seller, e.amount);
    }
    
    /**
     * @notice Seller claims funds after timeout (buyer unresponsive)
     * @param escrowId The escrow to claim
     */
    function claimAfterTimeout(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        require(e.state == EscrowState.Active, "Escrow not active");
        require(msg.sender == e.seller, "Only seller can claim");
        require(block.timestamp >= e.createdAt + e.timeoutSeconds, "Timeout not reached");
        
        e.state = EscrowState.Released;
        completedAsseller[e.seller]++;
        
        usdc.safeTransfer(e.seller, e.amount);
        
        emit EscrowReleased(escrowId, e.seller, e.amount);
    }
    
    /**
     * @notice Buyer requests refund (dispute initiation)
     * @dev Simple model: if disputed before timeout, funds return to buyer
     * @param escrowId The escrow to dispute
     */
    function dispute(uint256 escrowId) external nonReentrant {
        Escrow storage e = escrows[escrowId];
        require(e.state == EscrowState.Active, "Escrow not active");
        require(msg.sender == e.buyer, "Only buyer can dispute");
        require(block.timestamp < e.createdAt + e.timeoutSeconds, "Timeout passed");
        
        e.state = EscrowState.Refunded;
        
        usdc.safeTransfer(e.buyer, e.amount);
        
        emit EscrowRefunded(escrowId, e.buyer, e.amount);
    }
    
    /**
     * @notice Get escrow details
     */
    function getEscrow(uint256 escrowId) external view returns (
        address buyer,
        address seller,
        uint256 amount,
        uint256 createdAt,
        uint256 timeoutSeconds,
        EscrowState state,
        bytes32 serviceId
    ) {
        Escrow storage e = escrows[escrowId];
        return (e.buyer, e.seller, e.amount, e.createdAt, e.timeoutSeconds, e.state, e.serviceId);
    }
    
    /**
     * @notice Check if timeout has passed for an escrow
     */
    function isTimedOut(uint256 escrowId) external view returns (bool) {
        Escrow storage e = escrows[escrowId];
        return block.timestamp >= e.createdAt + e.timeoutSeconds;
    }
    
    /**
     * @notice Get agent stats
     */
    function getAgentStats(address agent) external view returns (
        uint256 completedSales,
        uint256 completedPurchases
    ) {
        return (completedAsseller[agent], completedAsBuyer[agent]);
    }
}
