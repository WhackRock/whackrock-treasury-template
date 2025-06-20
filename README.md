## Base Mainet Foundry Tested


### To run the tests on forked base main net:  

Add this to your foundry.toml:

```
# profile for Base mainnet forking
[profile.base_fork]
# Inherit from default profile
src = "src"
out = "out"
libs = ["lib"]
# Replace with your actual Base Mainnet RPC URL
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