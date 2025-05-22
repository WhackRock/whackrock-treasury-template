
### One-paragraph summary

*Think of WhackRock as an on-chain fund-platform.*
Each strategy lives in a little ERC-4626 **treasury vault**; a tiny Python **agent** decides how that vault should move its money; the moves are executed on **Uniswap V3 (Base network)**; and a plug-and-play **GAME-Python plugin** glues the Python agent to the vault.
Whenever someone deposits USDC or ETH the vault skims an up-front fee: **80 % goes straight to the strategy’s dev wallet, 20 % is paid to anyone staking WRK** (the WhackRock token).
That’s the whole loop.

---

## The pieces and how they click

| Step                                    | What happens                                                                                                                               | Which component does it                                               |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| **1. Deploy core contracts once**       | *Uni-TWAP oracle*, *Uniswap adapter*, and *Treasury Factory* are deployed to **Base**.                                                     | Solidity contracts (`UniTwapOracle`, `UniAdapter`, `WhackRockTreasuryFactory`) |
| **2. Spin up a new vault**              | Call `factory.createWhackRockVault(...)` with a list of tokens (e.g., stETH/WBTC/USDT) and the dev wallet.                                          | Treasury Factory → clone of `WeightedTreasuryVault`                   |
| **3. Start the Python agent**           | You clone the **agent template**, fill in `signals.py`, and run the worker.                                                                | GAME-Python plugin `whackrock-treasury`                               |
| **4. Agent decides weights**            | Every 30 min (or whatever) it computes new weights (e.g., `[0.55,0.35,0.10]`).                                                             | Your strategy code (`derive_weights()`)                               |
| **5. Agent rebalances**                 | If weights moved > 2 %, the agent: <br>• calls the vault’s `setWeights()` <br>• builds Universal-Router calldata <br>• calls `rebalance()` | Plugin helper functions (`set_and_rebalance`) + `UniAdapter`          |
| **6. Swaps execute on-chain**           | Universal Router trades inside the vault; balances now match the target weights.                                                           | Uniswap V3 liquidity on Base                                          |
| **7. Fee is distributed automatically** | On every new deposit the vault mints fee-shares: **80 %** to `devWallet`, **20 %** to the global `wrkRewards` pot.                         | Logic inside `WeightedTreasuryVault`                                  |
| **8. WRK stakers claim rewards**        | `wrkRewards` holds the 20 % slice; stakers call `harvest()` to pull their share.                                                           | `WrkRewards` contract                                                 |
| **9. Performance is tracked**           | Vault emits a `VaultState` event each time it changes; a **subgraph** stores daily price points → anyone can read PnL & Sharpe.            | The Graph + event indexer                                             |

---

### Data & control flow (ASCII)

```
Python Agent ──► GAME Plugin ──► setWeights + rebalance (tx)
                                            │
                                            ▼
                                WeightedTreasuryVault
                     (ERC-4626, fee logic, holds tokens)
                                            │ swaps via UniAdapter
                                            ▼
                                   Uniswap V3 pools
---

### What users see

* **Developers** fork the template, write one function, get 80 % of fees.
* **Investors** deposit USDC/ETH into a vault and can withdraw at any time.
* **WRK stakers** lock WRK and collect a slice of every vault’s fee stream.

Everything runs on **Base**, fully on-chain, using only Uniswap prices—no external servers or cron jobs required.

# Uniswap addresses (sepolia base and mainnet base):
https://docs.uniswap.org/contracts/v3/reference/deployments/base-deployments


# To deply:
 .\run-deploy.ps1
