# treasury-smart-contracts

treasury-smart-contracts/
├─ contracts/                ← Solidity sources (0.8.25)
│   ├─ core/
│   │   ├─ WeightedTreasuryVault.sol    # generic ERC‑4626
│   │   ├─ TreasuryFactory.sol         # deterministic clone deployer
│   │   ├─ FeeSplitter.sol             # fee sink + WRK buyback
│   │   └─ adapters/
│   │       ├─ UniAdapter.sol          # Universal Router wrapper
│   │       └─ UniTwapOracle.sol       # on‑chain TWAP oracle (no Chainlink)
│   └─ test/                           # Foundry tests (unit + fork)
├─ script/                             # Solidity deploy scripts
│   ├─ DeployCore.s.sol
│   └─ DeployAgentVault.s.sol