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

# Execute the command directly without capturing all stdout to a variable initially,
# so that forge's interactive prompts or verbose output are seen in real-time.
& $forgeExecutable $forgeCommandArgs

# Check if deployment and verification submission was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Deployment and Verification command submitted successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Forge will attempt to verify all deployed contracts on Basescan."
    Write-Host "This process might take a few minutes. Check the logs above for details and Basescan links."
    Write-Host "IMPORTANT: Contract addresses have been displayed in the logs above, and saved to the broadcast files." -ForegroundColor Yellow
    Write-Host "Broadcast file: broadcast/$($deploymentScriptName).s.sol/8453/run-latest.json" -ForegroundColor Yellow
    
    # --- VERIFY THE WHACKROCK FUND CREATED BY THE REGISTRY ---
    Write-Host ""
    Write-Host "=== Verifying WhackRockFund created by Registry ===" -ForegroundColor Cyan
    
    # Wait a moment for the broadcast file to be fully written
    Start-Sleep -Seconds 2
    
    # Parse the broadcast file
    $broadcastFile = "broadcast/$($deploymentScriptName).s.sol/8453/run-latest.json"
    
    if (Test-Path $broadcastFile) {
        try {
            $broadcastContent = Get-Content $broadcastFile -Raw | ConvertFrom-Json
            
            # Find the WhackRockFund creation transaction
            # Look for transactions where contractName is "WhackRockFund"
            $fundAddress = $null
            $fundTransaction = $null
            
            foreach ($tx in $broadcastContent.transactions) {
                if ($tx.contractName -eq "WhackRockFund") {
                    $fundAddress = $tx.contractAddress
                    $fundTransaction = $tx
                    break
                }
            }
            
            if ($fundAddress) {
                Write-Host "Found WhackRockFund at address: $fundAddress" -ForegroundColor Green
                
                # Extract constructor arguments from the transaction
                # The constructor args are in the transaction input after the bytecode
                # For WhackRockFund, we need to encode the constructor arguments
                
                # Get the deployer address from the broadcast
                $deployerAddress = $null
                foreach ($tx in $broadcastContent.transactions) {
                    if ($tx.transactionType -eq "CALL" -and $tx.function -contains "createWhackRockFund") {
                        # The 'from' field in a CALL transaction is the msg.sender
                        $deployerAddress = $tx.transaction.from
                        break
                    }
                }
                
                if (-not $deployerAddress) {
                    # Fallback: get from any transaction
                    $deployerAddress = $broadcastContent.transactions[0].transaction.from
                }
                
                Write-Host "Deployer address: $deployerAddress" -ForegroundColor Gray
                
                # Extract constructor arguments from the fund creation transaction
                # The constructor arguments are appended to the contract bytecode in the transaction data
                $constructorArgs = ""
                
                if ($fundTransaction.transaction.data) {
                    # Get the transaction data (bytecode + constructor args)
                    $txData = $fundTransaction.transaction.data
                    
                    # Method 1: Try to extract from the arguments field if available
                    if ($fundTransaction.arguments) {
                        Write-Host "Found constructor arguments in transaction metadata" -ForegroundColor Gray
                        
                        # The arguments are already parsed, we need to encode them
                        # This is complex, so we'll use Method 2 as primary approach
                    }
                    
                    # Method 2: Extract from raw transaction data
                    # The constructor args are at the end of the transaction data
                    # We need to find where the bytecode ends and constructor args begin
                    
                    # For WhackRockFund, the constructor has 13 parameters
                    # Each address parameter takes 32 bytes (64 hex chars)
                    # Dynamic arrays and strings have additional encoding
                    
                    # A more reliable approach: use forge to fetch the creation code
                    Write-Host "Fetching constructor arguments using forge..." -ForegroundColor Gray
                    
                    # Use forge's built-in functionality to get constructor args
                    $getConstructorArgsCmd = @(
                        "etherscan-contract-info",
                        "--chain", "8453",
                        $fundAddress
                    )
                    
                    try {
                        # First, let's try to get the full transaction data from the broadcast
                        # and extract constructor args from it
                        
                        # Find the length of the deployed bytecode to determine where constructor args start
                        # This is a simplified approach - in production, you might want to use
                        # the actual contract bytecode length
                        
                        # Alternative: Extract from transaction input
                        # Remove 0x prefix
                        $txDataClean = $txData -replace "^0x", ""
                        
                        # The constructor arguments are typically at the end of the creation code
                        # For a more robust solution, we'd need to know the exact bytecode length
                        # For now, we'll attempt to use the transaction's encoded arguments
                        
                        # Simplified: Take the last portion of the transaction data as constructor args
                        # This is an approximation - in production, calculate exact bytecode length
                        
                        # WhackRockFund has complex constructor with dynamic types
                        # It's safer to construct the args based on known values
                        
                        Write-Host "Using known deployment values to construct constructor arguments..." -ForegroundColor Gray
                        
                        # Parse values from the createWhackRockFund call
                        $createFundTx = $null
                        foreach ($tx in $broadcastContent.transactions) {
                            if ($tx.function -like "*createWhackRockFund*") {
                                $createFundTx = $tx
                                break
                            }
                        }
                        
                        if ($createFundTx -and $createFundTx.arguments) {
                            Write-Host "Found createWhackRockFund transaction with arguments" -ForegroundColor Gray
                            # Use the arguments from the createWhackRockFund call to construct the constructor args
                            # This is still complex due to ABI encoding requirements
                        }
                        
                        # Fallback to hardcoded values based on deployment script
                        # This matches the values in DeployWhackRockFundRegistry.s.sol
                        $constructorArgs = @"
$($deployerAddress.Substring(2).PadLeft(64, '0'))
$($deployerAddress.Substring(2).PadLeft(64, '0'))
000000000000000000000000cf77a3ba9a5ca399b7c97c74d54e5b1beb874e43
00000000000000000000000000000000000000000000000000000000000001a0
0000000000000000000000000000000000000000000000000000000000000340
00000000000000000000000000000000000000000000000000000000000004e0
0000000000000000000000000000000000000000000000000000000000000540
0000000000000000000000000000000000000000000000000000000000000580
$($deployerAddress.Substring(2).PadLeft(64, '0'))
00000000000000000000000000000000000000000000000000000000000000c8
00000000000000000000000090cfb07a46ee4bb20c970dda18aad1ba3c9450ae
000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913
00000000000000000000000000000000000000000000000000000000000005c0
0000000000000000000000000000000000000000000000000000000000000003
000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913
000000000000000000000000cbb7c0000ab88b473b1f5afd9ef808440eed33bf
0000000000000000000000000b3e328455c4059eeb9e3f84b5543f74e24e7e1b
0000000000000000000000000000000000000000000000000000000000000003
0000000000000000000000000000000000000000000000000000000000000fa0
0000000000000000000000000000000000000000000000000000000000001388
00000000000000000000000000000000000000000000000000000000000003e8
0000000000000000000000000000000000000000000000000000000000000019
42656e46616e2046756e6420627920576861636b526f636b0000000000000000
0000000000000000000000000000000000000000000000000000000000000005
4246575246000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000001f
68747470733a2f2f782e636f6d2f62656e6a41496d696e5f6167656e74000000
0000000000000000000000000000000000000000000000000000000000000000
"@ -replace "`r`n", "" -replace "`n", "" -replace " ", ""
                        
                        Write-Host "Note: Using predefined constructor arguments. For production, implement dynamic extraction." -ForegroundColor Yellow
                        
                    } catch {
                        Write-Host "Error extracting constructor arguments: $_" -ForegroundColor Yellow
                        Write-Host "Will attempt verification with default arguments" -ForegroundColor Yellow
                    }
                }
                
                Write-Host "Attempting to verify WhackRockFund..." -ForegroundColor Yellow
                
                # Run forge verify-contract command
                $verifyArgs = @(
                    "verify-contract",
                    $fundAddress,
                    "src/WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol:WhackRockFund",
                    "--chain", "8453",
                    "--etherscan-api-key", $actualBasescanApiKey,
                    "--constructor-args", "0x$constructorArgs",
                    "--watch"
                )
                
                Write-Host "Executing: $forgeExecutable $($verifyArgs -join ' ')"
                & $forgeExecutable $verifyArgs
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "WhackRockFund verification submitted successfully!" -ForegroundColor Green
                } else {
                    Write-Host "WhackRockFund verification failed. You may need to verify manually." -ForegroundColor Yellow
                    Write-Host "Manual verification command:" -ForegroundColor Gray
                    Write-Host "forge verify-contract $fundAddress src/WhackRockFundV5_ERC4626_Aerodrome_SubGEvents.sol:WhackRockFund --chain 8453 --constructor-args 0x$constructorArgs" -ForegroundColor Gray
                }
                
            } else {
                Write-Host "Could not find WhackRockFund address in broadcast file." -ForegroundColor Yellow
                Write-Host "The fund may need to be verified manually after checking the logs." -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "Error parsing broadcast file: $_" -ForegroundColor Red
            Write-Host "WhackRockFund will need to be verified manually." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Broadcast file not found: $broadcastFile" -ForegroundColor Yellow
        Write-Host "WhackRockFund will need to be verified manually." -ForegroundColor Yellow
    }
    
} else {
    Write-Host "Deployment or Verification submission failed. Check the logs for errors." -ForegroundColor Red
}