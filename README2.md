                   ┌───────────────────┐
                   │  WhackRockTreasuryFactory  │
                   └─────────┬─────────┘
                             │ creates
                             ▼
┌──────────────┐    ┌───────────────────────┐
│ UniTwapOracle│◄───┤ WeightedTreasuryVault │
└──────┬───────┘    └─────────┬─────────────┘
       │                      │
       │ implements           │ uses
       ▼                      ▼
┌──────────────┐    ┌───────────────┐
│ IPriceOracle │    │  UniAdapter   │
└──────────────┘    └───────┬───────┘
                            │
                            │ implements
                            ▼
                    ┌───────────────┐
                    │  ISwapAdapter │
                    └───────────────┘