# Load environment variables from .env file
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        if ($value -ne "" -or -not (Test-Path "Env:$name")) {
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

# --- CONFIGURATION ---
$deploymentScriptName = "DeployWhackRockFundRegistry" # Solidity script contract name
$deploymentScriptFile = "script/$($deploymentScriptName).s.sol" # Path to your deployment script

# --- DEPLOYMENT & VERIFICATION --- 
Write-Host "=== WhackRock Treasury Deployment & Verification to Base ===" -ForegroundColor Green
Write-Host "Loading environment from .env file..."
Write-Host "RPC URL: $($env:RPC_URL)"
Write-Host "Basescan API Key: $($env:BASESCAN_API_KEY -replace '.{20}$', '...')"
Write-Host ""

# Ask for confirmation
$confirmation = Read-Host "Continue with DEPLOYMENT and BUILT-IN VERIFICATION? (y/n)"
if ($confirmation -ne 'y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 1
}

Write-Host "Running forge script for deployment and verification..." -ForegroundColor Cyan

# Construct arguments for forge command
$forgeExecutable = "forge" # Assumes forge is in PATH
$scriptPathWithContract = "${deploymentScriptFile}:$($deploymentScriptName)"
$actualRpcUrl = $env:RPC_URL
$actualBasescanApiKey = $env:BASESCAN_API_KEY

$forgeCommandArgs = @(
    "script",
    $scriptPathWithContract,
    "--rpc-url", $actualRpcUrl,
    "--broadcast",
    "--verify",
    "--etherscan-api-key", $actualBasescanApiKey,
    "--slow",
    "--skip-simulation",
    "--with-gas-price", "2gwei",
    "-vvvv"
)

Write-Host "Executing: $forgeExecutable $($forgeCommandArgs -join ' ')"

# Capture the output to extract the fund address
$scriptOutput = & $forgeExecutable $forgeCommandArgs 2>&1 | Tee-Object -Variable outputLines
$scriptOutput | ForEach-Object { Write-Host $_ }

# Check if deployment and verification submission was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Deployment and Verification command submitted successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Forge will attempt to verify all deployed contracts on Basescan."
    Write-Host "This process might take a few minutes. Check the logs above for details and Basescan links."
    Write-Host "IMPORTANT: Contract addresses have been displayed in the logs above, and saved to the broadcast files." -ForegroundColor Yellow
    Write-Host "Broadcast file: broadcast/$($deploymentScriptName).s.sol/8453/run-latest.json" -ForegroundColor Yellow
    
    # --- VERIFY THE WHACKROCK FUND CREATED BY THE REGISTRY ---
    Write-Host ""
    Write-Host "=== Verifying WhackRockFund created by Registry ===" -ForegroundColor Cyan
    
    # First, try to extract fund address from the deployment output
    $fundAddress = $null
    foreach ($line in $outputLines) {
        if ($line -match "Dummy WhackRockFund created at:\s*(0x[a-fA-F0-9]{40})") {
            $fundAddress = $matches[1]
            Write-Host "Found fund address from deployment logs: $fundAddress" -ForegroundColor Green
            break
        }
    }
    
    # If not found in output, check the broadcast file
    if (-not $fundAddress) {
        Write-Host "Fund address not found in deployment output, checking broadcast file..." -ForegroundColor Gray
        
        # Wait a moment for the broadcast file to be fully written
        Start-Sleep -Seconds 2
        
        # Parse the broadcast file
        $broadcastFile = "broadcast/$($deploymentScriptName).s.sol/8453/run-latest.json"
        
        if (Test-Path $broadcastFile) {
            try {
                $broadcastContent = Get-Content $broadcastFile -Raw | ConvertFrom-Json
                
                # Look for the createWhackRockFund transaction
                foreach ($tx in $broadcastContent.transactions) {
                    if ($tx.function -like "*createWhackRockFund*") {
                        Write-Host "Found createWhackRockFund transaction" -ForegroundColor Gray
                        
                        # Check if there are any additional contracts created (the fund)
                        if ($tx.additionalContracts) {
                            foreach ($contract in $tx.additionalContracts) {
                                if ($contract.transactionType -eq "CREATE" -or $contract.transactionType -eq "CREATE2") {
                                    $fundAddress = $contract.address
                                    Write-Host "Found fund address from additionalContracts: $fundAddress" -ForegroundColor Green
                                    break
                                }
                            }
                        }
                        
                        # If still not found, check transaction receipts
                        if (-not $fundAddress -and $tx.receipt -and $tx.receipt.logs) {
                            foreach ($log in $tx.receipt.logs) {
                                # Look for contract creation in logs (usually topic0 is the event signature)
                                if ($log.address -and $log.topics -and $log.topics.Count -gt 0) {
                                    # Fund address might be in the event data
                                    Write-Host "Checking log from address: $($log.address)" -ForegroundColor Gray
                                }
                            }
                        }
                        break
                    }
                }
                
                # As a last resort, look for any WhackRockFund contract in the transactions
                if (-not $fundAddress) {
                    foreach ($tx in $broadcastContent.transactions) {
                        if ($tx.contractName -eq "WhackRockFund") {
                            $fundAddress = $tx.contractAddress
                            Write-Host "Found WhackRockFund in transactions: $fundAddress" -ForegroundColor Green
                            break
                        }
                    }
                }
            } catch {
                Write-Host "Error parsing broadcast file: $_" -ForegroundColor Red
            }
        }
    }
    
    # If we found the fund address, verify it
    if ($fundAddress) {
        Write-Host ""
        Write-Host "Preparing to verify WhackRockFund at: $fundAddress" -ForegroundColor Cyan
        
        # Get deployer address from environment or broadcast
        $deployerAddress = $null
        
        # Try to get from broadcast file
        if ($broadcastContent -and $broadcastContent.transactions -and $broadcastContent.transactions.Count -gt 0) {
            $deployerAddress = $broadcastContent.transactions[0].transaction.from
            Write-Host "Found deployer address from broadcast file: $deployerAddress" -ForegroundColor Gray
        }
        
        # If still not found, try to parse from the output
        if (-not $deployerAddress) {
            foreach ($line in $outputLines) {
                if ($line -match "Deployer Address:\s*(0x[a-fA-F0-9]{40})") {
                    $deployerAddress = $matches[1]
                    Write-Host "Found deployer address from deployment logs: $deployerAddress" -ForegroundColor Gray
                    break
                }
            }
        }
        
        # Fallback to hardcoded address from deployment script
        if (-not $deployerAddress) {
            $deployerAddress = "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae"
            Write-Host "Using default deployer address: $deployerAddress" -ForegroundColor Yellow
        }
        
        Write-Host "Deployer address: $deployerAddress" -ForegroundColor Cyan
        
        # Encode constructor arguments for WhackRockFund V6 (UniSwap TWAP version)
        # Based on the deployment script, these are the parameters:
        Write-Host "Encoding constructor arguments..." -ForegroundColor Gray
        
        # Use cast abi-encode for encoding constructor arguments
        $castExecutable = "cast" # Assumes cast is in PATH
        $constructorEncodeArgs = @(
            "abi-encode",
            '"constructor(address,address,address,address,address,address,address[],uint256[],string,string,string,address,uint256,address,address,string)"',
            $deployerAddress,  # _initialOwner
            $deployerAddress,  # _initialAgent
            "0x2626664c2603336E57B271c5C0b26F421741e481", # _uniswapV3RouterAddress
            "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a", # _uniswapV3QuoterAddress
            "0x33128a8fC17869897dcE68Ed026d694621f6FDfD", # _uniswapV3FactoryAddress
            "0x4200000000000000000000000000000000000006", # _wethAddress
            "[0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,0x0b3e328455c4059EEb9e3f84b5543F74e24e7E1b]", # _fundAllowedTokens
            "[4000,5000,1000]", # _initialTargetWeights
            '"BenFan Fund by WhackRock"', # _vaultName
            '"BFWRF"', # _vaultSymbol
            '"https://x.com/benjAImin_agent"', # _vaultURI
            $deployerAddress, # _agentAumFeeWalletForFund
            "200", # _agentSetTotalAumFeeBps
            "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae", # _protocolAumFeeRecipientForFunds
            "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", # _usdcTokenAddress
            '""' # data (empty string)
        )
        
        try {
            $constructorArgs = & $castExecutable $constructorEncodeArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                $constructorArgs = $constructorArgs.Trim()
                Write-Host "Constructor arguments encoded successfully" -ForegroundColor Green
            } else {
                throw "Failed to encode constructor arguments: $constructorArgs"
            }
        } catch {
            Write-Host "Error encoding constructor arguments: $_" -ForegroundColor Yellow
            Write-Host "Using fallback hardcoded constructor arguments" -ForegroundColor Yellow
            
            # Ensure deployer address exists for fallback
            if (-not $deployerAddress) {
                $deployerAddress = "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae"
                Write-Host "Using fallback deployer address: $deployerAddress" -ForegroundColor Yellow
            }
            
            # Fallback: use pre-encoded args (this is less ideal but works)
            # Note: This is a simplified encoding - for production use, generate the full encoded args
            $deployerAddressHex = $deployerAddress.Substring(2).ToLower().PadLeft(64, '0')
            $constructorArgs = "0x" + 
                              $deployerAddressHex + # _initialOwner
                              $deployerAddressHex + # _initialAgent
                              "0000000000000000000000002626664c2603336e57b271c5c0b26f421741e481" + # router
                              "0000000000000000000000003d4e44eb1374240ce5f1b871ab261cd16335b76a" + # quoter
                              "00000000000000000000000033128a8fc17869897dce68ed026d694621f6fdfd" + # factory
                              "0000000000000000000000004200000000000000000000000000000000000006"   # WETH
            # ... (truncated for brevity, would need full encoding with arrays and strings)
            
            Write-Host "Note: Fallback encoding is incomplete. Manual verification may be required." -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "Verifying WhackRockFund contract..." -ForegroundColor Yellow
        
        # Run forge verify-contract command
        $verifyArgs = @(
            "verify-contract",
            $fundAddress,
            "src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund",
            "--chain", "8453",
            "--etherscan-api-key", $actualBasescanApiKey,
            "--constructor-args", $constructorArgs,
            "--watch"
        )
        
        Write-Host "Executing: $forgeExecutable $($verifyArgs -join ' ')"
        & $forgeExecutable $verifyArgs
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "WhackRockFund verification submitted successfully!" -ForegroundColor Green
            Write-Host "Check Basescan for verification status: https://basescan.org/address/$fundAddress#code" -ForegroundColor Cyan
        } else {
            Write-Host ""
            Write-Host "WhackRockFund verification failed." -ForegroundColor Yellow
            Write-Host "You may need to verify manually on Basescan." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Manual verification steps:" -ForegroundColor Cyan
            Write-Host "1. Go to: https://basescan.org/address/$fundAddress#code" -ForegroundColor Gray
            Write-Host "2. Click 'Verify and Publish'" -ForegroundColor Gray
            Write-Host "3. Select:" -ForegroundColor Gray
            Write-Host "   - Compiler Type: Solidity (Single file)" -ForegroundColor Gray
            Write-Host "   - Compiler Version: v0.8.20+commit.a1b79de6" -ForegroundColor Gray
            Write-Host "   - License: MIT" -ForegroundColor Gray
            Write-Host "4. Paste the flattened contract source" -ForegroundColor Gray
            Write-Host "5. Constructor Arguments: $($constructorArgs -replace '^0x', '')" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Or use the command line:" -ForegroundColor Cyan
            Write-Host "forge verify-contract $fundAddress src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund --chain 8453 --constructor-args $constructorArgs --etherscan-api-key YOUR_API_KEY" -ForegroundColor Gray
        }
        
    } else {
        Write-Host ""
        Write-Host "Could not find WhackRockFund address automatically." -ForegroundColor Yellow
        Write-Host "Please check the deployment logs above for a line like:" -ForegroundColor Yellow
        Write-Host "'Dummy WhackRockFund created at: 0x...'" -ForegroundColor Gray
        Write-Host ""
        
        # Ask user if they want to manually provide the fund address
        $manualAddress = Read-Host "Enter the WhackRockFund address to verify (or press Enter to skip)"
        
        if ($manualAddress -and $manualAddress -match '^0x[a-fA-F0-9]{40}$') {
            $fundAddress = $manualAddress
            Write-Host ""
            Write-Host "Manual verification of WhackRockFund at: $fundAddress" -ForegroundColor Cyan
            
            # Get deployer address
            $deployerAddress = Read-Host "Enter the deployer address (or press Enter to use default)"
            if (-not $deployerAddress) {
                $deployerAddress = "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae" # Default from script
            }
            
            # Provide manual verification command
            Write-Host ""
            Write-Host "To verify manually, use this command:" -ForegroundColor Cyan
            Write-Host "forge verify-contract $fundAddress src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund --chain 8453 --constructor-args <ENCODED_ARGS> --etherscan-api-key $($env:BASESCAN_API_KEY)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "You'll need to encode the constructor arguments based on the actual deployment parameters." -ForegroundColor Yellow
        }
    }
    
} else {
    Write-Host "Deployment or Verification submission failed. Check the logs for errors." -ForegroundColor Red
}