/**
 * Agent Economy Escrow API
 * Circle USDC Hackathon - Agentic Commerce Track
 * 
 * This API allows AI agents to interact with USDC escrow on Base Sepolia.
 * Agents can create escrows, release funds, and check status programmatically.
 */

const { ethers } = require('ethers');
const express = require('express');

// Contract ABI (minimal interface for agents)
const ESCROW_ABI = [
  "function createEscrow(address seller, uint256 amount, uint256 timeoutSeconds, bytes32 serviceId) external returns (uint256)",
  "function release(uint256 escrowId) external",
  "function claimAfterTimeout(uint256 escrowId) external",
  "function dispute(uint256 escrowId) external",
  "function getEscrow(uint256 escrowId) external view returns (address buyer, address seller, uint256 amount, uint256 createdAt, uint256 timeoutSeconds, uint8 state, bytes32 serviceId)",
  "function isTimedOut(uint256 escrowId) external view returns (bool)",
  "function getAgentStats(address agent) external view returns (uint256 completedSales, uint256 completedPurchases)",
  "function escrowCount() external view returns (uint256)",
  "event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 amount, bytes32 serviceId)",
  "event EscrowReleased(uint256 indexed escrowId, address indexed seller, uint256 amount)",
  "event EscrowRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount)"
];

const USDC_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
  "function allowance(address owner, address spender) external view returns (uint256)"
];

// Configuration
const CONFIG = {
  rpcUrl: process.env.RPC_URL || 'https://sepolia.base.org',
  escrowAddress: process.env.ESCROW_ADDRESS || 'TBD', // Will be set after deployment
  usdcAddress: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia USDC
  chainId: 84532, // Base Sepolia
};

class EscrowAPI {
  constructor(privateKey) {
    this.provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
    this.wallet = new ethers.Wallet(privateKey, this.provider);
    this.escrow = new ethers.Contract(CONFIG.escrowAddress, ESCROW_ABI, this.wallet);
    this.usdc = new ethers.Contract(CONFIG.usdcAddress, USDC_ABI, this.wallet);
  }

  /**
   * Get agent's USDC balance
   */
  async getBalance() {
    const balance = await this.usdc.balanceOf(this.wallet.address);
    return {
      address: this.wallet.address,
      usdc: ethers.formatUnits(balance, 6),
      raw: balance.toString()
    };
  }

  /**
   * Approve USDC for escrow contract
   */
  async approveUSDC(amount) {
    const amountWei = ethers.parseUnits(amount.toString(), 6);
    const tx = await this.usdc.approve(CONFIG.escrowAddress, amountWei);
    await tx.wait();
    return { txHash: tx.hash, approved: amount };
  }

  /**
   * Create a new escrow for a service purchase
   * @param {string} seller - Seller's wallet address
   * @param {number} amount - USDC amount (human readable, e.g., 100 for 100 USDC)
   * @param {number} timeoutHours - Hours until seller can claim if buyer unresponsive
   * @param {string} serviceId - Reference to the service being purchased
   */
  async createEscrow(seller, amount, timeoutHours, serviceId) {
    const amountWei = ethers.parseUnits(amount.toString(), 6);
    const timeoutSeconds = timeoutHours * 3600;
    const serviceIdBytes = ethers.id(serviceId);
    
    // Check allowance
    const allowance = await this.usdc.allowance(this.wallet.address, CONFIG.escrowAddress);
    if (allowance < amountWei) {
      throw new Error(`Insufficient USDC allowance. Call approveUSDC(${amount}) first.`);
    }
    
    const tx = await this.escrow.createEscrow(seller, amountWei, timeoutSeconds, serviceIdBytes);
    const receipt = await tx.wait();
    
    // Parse escrowId from events
    const event = receipt.logs.find(log => {
      try {
        return this.escrow.interface.parseLog(log)?.name === 'EscrowCreated';
      } catch { return false; }
    });
    
    const parsed = this.escrow.interface.parseLog(event);
    
    return {
      escrowId: parsed.args.escrowId.toString(),
      buyer: parsed.args.buyer,
      seller: parsed.args.seller,
      amount: amount,
      txHash: tx.hash
    };
  }

  /**
   * Release escrow funds to seller (buyer confirms service delivered)
   */
  async release(escrowId) {
    const tx = await this.escrow.release(escrowId);
    await tx.wait();
    return { escrowId, status: 'released', txHash: tx.hash };
  }

  /**
   * Claim funds after timeout (seller claims if buyer unresponsive)
   */
  async claimAfterTimeout(escrowId) {
    const tx = await this.escrow.claimAfterTimeout(escrowId);
    await tx.wait();
    return { escrowId, status: 'claimed', txHash: tx.hash };
  }

  /**
   * Dispute and refund (buyer disputes before timeout)
   */
  async dispute(escrowId) {
    const tx = await this.escrow.dispute(escrowId);
    await tx.wait();
    return { escrowId, status: 'refunded', txHash: tx.hash };
  }

  /**
   * Get escrow details
   */
  async getEscrow(escrowId) {
    const [buyer, seller, amount, createdAt, timeoutSeconds, state, serviceId] = 
      await this.escrow.getEscrow(escrowId);
    
    const states = ['Active', 'Released', 'Refunded', 'Disputed'];
    const isTimedOut = await this.escrow.isTimedOut(escrowId);
    
    return {
      escrowId,
      buyer,
      seller,
      amount: ethers.formatUnits(amount, 6),
      createdAt: new Date(Number(createdAt) * 1000).toISOString(),
      timeoutAt: new Date((Number(createdAt) + Number(timeoutSeconds)) * 1000).toISOString(),
      state: states[state],
      serviceId,
      isTimedOut
    };
  }

  /**
   * Get agent reputation stats
   */
  async getAgentStats(address) {
    const [sales, purchases] = await this.escrow.getAgentStats(address || this.wallet.address);
    return {
      address: address || this.wallet.address,
      completedSales: sales.toString(),
      completedPurchases: purchases.toString(),
      totalTransactions: (Number(sales) + Number(purchases)).toString()
    };
  }

  /**
   * Get total escrow count
   */
  async getEscrowCount() {
    const count = await this.escrow.escrowCount();
    return { count: count.toString() };
  }
}

// Express server for HTTP API
function createServer(privateKey) {
  const app = express();
  app.use(express.json());
  
  const api = new EscrowAPI(privateKey);
  
  // Health check
  app.get('/health', (req, res) => {
    res.json({ 
      status: 'ok', 
      network: 'base-sepolia',
      escrowContract: CONFIG.escrowAddress,
      usdcContract: CONFIG.usdcAddress
    });
  });
  
  // Get balance
  app.get('/balance', async (req, res) => {
    try {
      const result = await api.getBalance();
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Approve USDC
  app.post('/approve', async (req, res) => {
    try {
      const { amount } = req.body;
      const result = await api.approveUSDC(amount);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Create escrow
  app.post('/escrow', async (req, res) => {
    try {
      const { seller, amount, timeoutHours, serviceId } = req.body;
      const result = await api.createEscrow(seller, amount, timeoutHours || 24, serviceId);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Get escrow
  app.get('/escrow/:id', async (req, res) => {
    try {
      const result = await api.getEscrow(req.params.id);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Release escrow
  app.post('/escrow/:id/release', async (req, res) => {
    try {
      const result = await api.release(req.params.id);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Dispute escrow
  app.post('/escrow/:id/dispute', async (req, res) => {
    try {
      const result = await api.dispute(req.params.id);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Claim after timeout
  app.post('/escrow/:id/claim', async (req, res) => {
    try {
      const result = await api.claimAfterTimeout(req.params.id);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Get agent stats
  app.get('/stats/:address?', async (req, res) => {
    try {
      const result = await api.getAgentStats(req.params.address);
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  // Get escrow count
  app.get('/count', async (req, res) => {
    try {
      const result = await api.getEscrowCount();
      res.json(result);
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });
  
  return app;
}

// CLI usage
if (require.main === module) {
  const port = process.env.PORT || 3002;
  const privateKey = process.env.PRIVATE_KEY;
  
  if (!privateKey) {
    console.error('PRIVATE_KEY environment variable required');
    process.exit(1);
  }
  
  const app = createServer(privateKey);
  app.listen(port, () => {
    console.log(`Agent Economy Escrow API running on port ${port}`);
    console.log(`Network: Base Sepolia`);
    console.log(`Escrow Contract: ${CONFIG.escrowAddress}`);
  });
}

module.exports = { EscrowAPI, createServer, CONFIG };
