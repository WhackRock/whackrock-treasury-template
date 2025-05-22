const { ethers } = require('ethers');
require('dotenv').config();

// Configuration - Update with your pool addresses
const config = {
  rpcUrl: process.env.RPC_URL || "https://mainnet.base.org",
  privateKey: process.env.PRIVATE_KEY,
  oracleAddress: "0xFA58249eD3239AE7dFA8Df30eDa9d7C3B51292D4",
  wethAddress: "0x4200000000000000000000000000000000000006",
  usdcAddress: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  // Tokens and their pool information
  tokenPairs: [
    {
      token: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", // BTC token
      pool: "0x8c7080564B5A792A33Ef2FD473fbA6364d5495e5", // WETH/BTC pool
      viaWeth: true // Set to true if token pairs with WETH, false if with USDC directly
    },
    {
      token: "0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b", // Virtuals token
      pool: "0xE31c372a7Af875b3B5E0F3713B17ef51556da667", // WETH/Virtuals pool
      viaWeth: true // Set to true if token pairs with WETH, false if with USDC directly
    }
  ]
};

// Oracle ABI - just the setPairs function
const ORACLE_ABI = [
  {
    "inputs": [
      {
        "internalType": "address[]",
        "name": "tokens",
        "type": "address[]"
      },
      {
        "internalType": "address[]",
        "name": "pools",
        "type": "address[]"
      },
      {
        "internalType": "bool[]",
        "name": "viaWeth",
        "type": "bool[]"
      }
    ],
    "name": "setPairs",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "token",
        "type": "address"
      }
    ],
    "name": "usdPrice",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "priceUsd1e18",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

// Uniswap V3 Pool ABI - just the token0 and token1 functions
const POOL_ABI = [
  {
    "inputs": [],
    "name": "token0",
    "outputs": [{ "internalType": "address", "name": "", "type": "address" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "token1",
    "outputs": [{ "internalType": "address", "name": "", "type": "address" }],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      { "internalType": "uint32[]", "name": "secondsAgos", "type": "uint32[]" }
    ],
    "name": "observe",
    "outputs": [
      { "internalType": "int56[]", "name": "tickCumulatives", "type": "int56[]" },
      { "internalType": "uint160[]", "name": "secondsPerLiquidityCumulativeX128s", "type": "uint160[]" }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

async function checkPoolConfiguration(provider, pair) {
  console.log(`\nChecking pool configuration for token: ${pair.token}`);
  try {
    const pool = new ethers.Contract(pair.pool, POOL_ABI, provider);
    
    // Get tokens in pool
    const token0 = await pool.token0();
    const token1 = await pool.token1();
    
    console.log(`Pool tokens: ${token0} and ${token1}`);
    
    // Check if the pool contains the token
    const poolHasToken = (token0.toLowerCase() === pair.token.toLowerCase() || 
                           token1.toLowerCase() === pair.token.toLowerCase());
    if (!poolHasToken) {
      console.error(`ERROR: Pool does not contain the token ${pair.token}`);
      return false;
    }
    
    // Check if pool configuration matches viaWeth setting
    if (pair.viaWeth) {
      // Should have WETH as one of the tokens
      const poolHasWeth = (token0.toLowerCase() === config.wethAddress.toLowerCase() || 
                            token1.toLowerCase() === config.wethAddress.toLowerCase());
      if (!poolHasWeth) {
        console.error(`ERROR: Pool does not contain WETH, but viaWeth is set to true`);
        return false;
      }
    } else {
      // Should have USDC as one of the tokens
      const poolHasUsdc = (token0.toLowerCase() === config.usdcAddress.toLowerCase() || 
                           token1.toLowerCase() === config.usdcAddress.toLowerCase());
      if (!poolHasUsdc) {
        console.error(`ERROR: Pool does not contain USDC, but viaWeth is set to false`);
        return false;
      }
    }
    
    console.log(`Pool configuration looks correct for token ${pair.token}`);
    return true;
  } catch (error) {
    console.error(`Error checking pool configuration: ${error.message}`);
    return false;
  }
}

async function main() {
  if (!config.privateKey) {
    console.error("Error: Private key not found. Set the PRIVATE_KEY environment variable.");
    process.exit(1);
  }

  try {
    // Setup provider and wallet
    const provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
    const wallet = new ethers.Wallet(config.privateKey, provider);
    
    // Check pool configurations before proceeding
    console.log("Validating pool configurations...");
    const validPairs = [];
    
    for (const pair of config.tokenPairs) {
      const isValid = await checkPoolConfiguration(provider, pair);
      if (isValid) {
        validPairs.push(pair);
      } else {
        console.log(`Skipping token ${pair.token} due to invalid pool configuration`);
      }
    }
    
    if (validPairs.length === 0) {
      console.error("No valid pool configurations found. Cannot continue.");
      process.exit(1);
    }
    
    // Get contract instance
    const oracle = new ethers.Contract(config.oracleAddress, ORACLE_ABI, wallet);
    
    // Prepare arrays for setPairs
    const tokens = validPairs.map(pair => pair.token);
    const pools = validPairs.map(pair => pair.pool);
    const viaWethFlags = validPairs.map(pair => pair.viaWeth);
    
    console.log("\nSetting pairs on oracle:", config.oracleAddress);
    console.log("Token addresses:", tokens);
    console.log("Pool addresses:", pools);
    console.log("ViaWeth flags:", viaWethFlags);
    
    // Send transaction
    const tx = await oracle.setPairs(tokens, pools, viaWethFlags);
    console.log("Transaction sent, hash:", tx.hash);
    
    // Wait for confirmation
    console.log("Waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("Transaction confirmed in block:", receipt.blockNumber);
    
    // Verify setup by checking a token price
    console.log("\nVerifying setup by checking token prices:");
    for (const pair of validPairs) {
      try {
        const price = await oracle.usdPrice(pair.token);
        console.log(`Price of token ${pair.token}: $${ethers.utils.formatUnits(price, 18)}`);
      } catch (error) {
        console.error(`Error getting price for token ${pair.token}:`, error.message);
        console.log("You may need to check this pool configuration manually.");
      }
    }
    
    console.log("\nSetup complete!");
  } catch (error) {
    console.error("Error:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    process.exit(1);
  }
}

main(); 