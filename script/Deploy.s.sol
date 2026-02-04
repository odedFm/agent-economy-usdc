// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentEscrow.sol";

contract DeployScript is Script {
    // Base Sepolia USDC (Circle's testnet USDC)
    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AgentEscrow escrow = new AgentEscrow(BASE_SEPOLIA_USDC);
        
        console.log("AgentEscrow deployed to:", address(escrow));
        console.log("USDC address:", BASE_SEPOLIA_USDC);
        
        vm.stopBroadcast();
    }
}
