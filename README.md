## Base Mainet Foundry Tested

###
UniswapV3 pools:

WETH/USDC=0xd0b53D9277642d899DF5C87A3966A349A798F224
WETH/rETH=0x9e13996A9f5a9870C105D7e3C311848273740e98
WETH/cbBTC=0x7AeA2E8A3843516afa07293a10Ac8E49906dabD1
WETH/VIRTUAL=0x9c087Eb773291e50CF6c6a90ef0F4500e349B903
WETH/TOSHI=0x4b0Aaf3EBb163dd45F663b38b6d93f6093EBC2d3
WETH/BRETT=0x76Bf0abD20f1e0155Ce40A62615a90A709a6C3D8

And:  https://docs.uniswap.org/contracts/v3/reference/deployments/base-deployments


### To run the tests on forked base main net:  

Add this to your foundry.toml:

```
# profile for Base mainnet forking
[profile.base_fork]
# Inherit from default profile
src = "src"
out = "out"
libs = ["lib"]
fork_url = "https://mainnet.base.org"
fork_block_number = 30483478 
```
Set profile to base_fork:
```
$env:FOUNDRY_PROFILE="base_fork"
```
Then test:
```
forge test --fork-url "https://mainnet.base.org"  -vvvv
```