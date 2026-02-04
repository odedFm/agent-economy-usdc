// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentEscrow.sol";

contract DeployScript is Script {
    // Arbitrum Sepolia USDC (Circle's testnet USDC)
    address constant ARB_SEPOLIA_USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AgentEscrow escrow = new AgentEscrow(ARB_SEPOLIA_USDC);
        
        console.log("AgentEscrow deployed to:", address(escrow));
        console.log("USDC address:", ARB_SEPOLIA_USDC);
        
        vm.stopBroadcast();
    }
}
