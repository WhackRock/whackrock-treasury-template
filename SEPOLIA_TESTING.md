# WhackRock Treasury - Sepolia Testing Guide

This guide will walk you through the process of deploying and testing the WhackRock Treasury contracts on Sepolia testnet.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- [NodeJS](https://nodejs.org/) and npm installed (for frontend testing)
- Sepolia ETH (from a [faucet](https://sepoliafaucet.com/))
- Metamask or another wallet with a Sepolia network configured

## Setup Environment

1. Clone the repository and navigate to the directory:
   ```bash
   cd treasury-smart-contracts
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Create a `.env` file from the example:
   ```bash
   cp sepolia.env.example .env
   ```

4. Edit the `.env` file with your specific values:
   - Add your private key
   - Set up an RPC URL for Sepolia (Infura, Alchemy, etc.)
   - Add your Etherscan API key if you plan to verify contracts

## Getting Testnet Tokens

1. **Get Sepolia ETH**
   - Visit [Sepolia Faucet](https://sepoliafaucet.com/) and follow the instructions

2. **Get Sepolia USDC**
   - After you have Sepolia ETH, you can get test USDC from Uniswap V3 on Sepolia
   - Visit [Uniswap on Sepolia](https://app.uniswap.org/#/swap?chain=sepolia) and swap some ETH for USDC

3. **Get Sepolia WBTC**
   - Similarly, you can get test WBTC from Uniswap by swapping ETH for WBTC

## Deployment to Sepolia

1. Deploy the contracts to Sepolia:
   ```bash
   forge script script/DeploySepolia.s.sol:DeploySepoliaScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
   ```

2. If you want to verify the contracts on Etherscan:
   ```bash
   forge script script/DeploySepolia.s.sol:DeploySepoliaScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   ```

3. Take note of the deployed addresses in the console output

## Interacting with Deployed Contracts

### Using Forge

You can use Forge's cast commands to interact with the deployed contracts:

```bash
# Check vault balance
cast call $SAMPLE_VAULT_ADDRESS "balanceOf(address)(uint256)" $YOUR_ADDRESS --rpc-url $SEPOLIA_RPC_URL

# Get current weights
cast call $SAMPLE_VAULT_ADDRESS "targetWeights(uint256)(uint256)" 0 --rpc-url $SEPOLIA_RPC_URL
```

### Using Game-Python Plugin

1. Update the `game-python-WR-package/plugins/WRTreasury/.env` file with your contract addresses:
   ```
   BASE_TESTNET_RPC=https://sepolia.infura.io/v3/your_api_key
   TREASURY_VAULT_ADDRESS=your_deployed_vault_address
   TREASURY_SIGNER_KEY=your_private_key
   ```

2. Run the example agent:
   ```bash
   cd game-python-WR-package
   game run plugins/WRTreasury/examples/template_agent/worker.py
   ```

## Testing Rebalance Functionality

1. Set new target weights:
   ```bash
   cast send $SAMPLE_VAULT_ADDRESS "setWeights(uint256[])" "[6000, 2000, 2000]" --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

2. Execute a rebalance:
   ```bash
   # Prepare rebalance data (example - adapt as needed)
   REBALANCE_DATA=$(cast abi-encode "execute(bytes)" $(cast abi-encode "data(bytes)" "0x"))
   
   # Call rebalance
   cast send $SAMPLE_VAULT_ADDRESS "rebalance(bytes)" $REBALANCE_DATA --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

## Building a Simple Frontend

For testing with a frontend, you can create a simple React app:

```bash
npx create-react-app whackrock-testnet-frontend
cd whackrock-testnet-frontend
npm install ethers@5.7.2 @usedapp/core
```

Add the following to your `src/config.js`:
```javascript
export const SEPOLIA_ADDRESSES = {
  factory: 'YOUR_FACTORY_ADDRESS',
  sampleVault: 'YOUR_SAMPLE_VAULT_ADDRESS',
  weth: '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9',
  usdc: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
  wbtc: '0xFF82bB6DB46Ad45F017e2Dfb478102C7D9a69397',
};
```

## Troubleshooting

- **Not enough ETH for gas**: Make sure you have enough Sepolia ETH for transactions
- **Transaction reverts**: Check the contract requirements and parameters
- **RPC errors**: Try using a different RPC provider if you encounter rate limits or connection issues

## Next Steps

1. **Monitor Performance**: Track your vault's performance on the Sepolia testnet
2. **Integrate with Ben Cowan Agent**: Configure the Ben Cowan agent to work with your deployed vault
3. **Test Multi-User Scenarios**: Have multiple users interact with the vault to simulate real-world usage

## Resources

- [Sepolia Etherscan](https://sepolia.etherscan.io/) - View deployed contracts and transactions
- [Uniswap Sepolia](https://app.uniswap.org/#/swap?chain=sepolia) - Get test tokens
- [Foundry Book](https://book.getfoundry.sh/) - Documentation for Foundry tools 