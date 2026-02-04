// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 10**6); // 1M USDC
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AgentEscrowTest is Test {
    AgentEscrow public escrow;
    MockUSDC public usdc;
    
    address buyer = address(0xB0B);
    address seller = address(0x5E11);
    
    uint256 constant AMOUNT = 100 * 10**6; // 100 USDC
    uint256 constant TIMEOUT = 1 days;
    bytes32 constant SERVICE_ID = keccak256("code-review-service-1");
    
    function setUp() public {
        usdc = new MockUSDC();
        escrow = new AgentEscrow(address(usdc));
        
        // Fund buyer
        usdc.mint(buyer, AMOUNT * 10);
        
        // Buyer approves escrow contract
        vm.prank(buyer);
        usdc.approve(address(escrow), type(uint256).max);
    }
    
    function test_CreateEscrow() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        assertEq(escrowId, 0);
        assertEq(usdc.balanceOf(address(escrow)), AMOUNT);
        assertEq(usdc.balanceOf(buyer), AMOUNT * 10 - AMOUNT);
        
        (
            address _buyer,
            address _seller,
            uint256 _amount,
            ,
            uint256 _timeout,
            AgentEscrow.EscrowState _state,
            bytes32 _serviceId
        ) = escrow.getEscrow(escrowId);
        
        assertEq(_buyer, buyer);
        assertEq(_seller, seller);
        assertEq(_amount, AMOUNT);
        assertEq(_timeout, TIMEOUT);
        assertEq(uint8(_state), uint8(AgentEscrow.EscrowState.Active));
        assertEq(_serviceId, SERVICE_ID);
    }
    
    function test_Release() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        
        vm.prank(buyer);
        escrow.release(escrowId);
        
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), 0);
        
        (,,,,,AgentEscrow.EscrowState state,) = escrow.getEscrow(escrowId);
        assertEq(uint8(state), uint8(AgentEscrow.EscrowState.Released));
        
        // Check stats updated
        (uint256 sales, ) = escrow.getAgentStats(seller);
        assertEq(sales, 1);
    }
    
    function test_ClaimAfterTimeout() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        // Warp past timeout
        vm.warp(block.timestamp + TIMEOUT + 1);
        
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        
        vm.prank(seller);
        escrow.claimAfterTimeout(escrowId);
        
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + AMOUNT);
    }
    
    function test_Dispute() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        
        vm.prank(buyer);
        escrow.dispute(escrowId);
        
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + AMOUNT);
        
        (,,,,,AgentEscrow.EscrowState state,) = escrow.getEscrow(escrowId);
        assertEq(uint8(state), uint8(AgentEscrow.EscrowState.Refunded));
    }
    
    function test_RevertDisputeAfterTimeout() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        // Warp past timeout
        vm.warp(block.timestamp + TIMEOUT + 1);
        
        vm.prank(buyer);
        vm.expectRevert("Timeout passed");
        escrow.dispute(escrowId);
    }
    
    function test_RevertClaimBeforeTimeout() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        vm.prank(seller);
        vm.expectRevert("Timeout not reached");
        escrow.claimAfterTimeout(escrowId);
    }
    
    function test_RevertDoubleRelease() public {
        vm.prank(buyer);
        uint256 escrowId = escrow.createEscrow(seller, AMOUNT, TIMEOUT, SERVICE_ID);
        
        vm.prank(buyer);
        escrow.release(escrowId);
        
        vm.prank(buyer);
        vm.expectRevert("Escrow not active");
        escrow.release(escrowId);
    }
}
