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
    
    # Parse the broadcast file to find the fund address
    $broadcastFile = "broadcast/$($deploymentScriptName).s.sol/8453/run-latest.json"
    
    if (Test-Path $broadcastFile) {
        try {
            $broadcastContent = Get-Content $broadcastFile -Raw | ConvertFrom-Json
            
            # Find the WhackRockFund creation transaction
            # Since the fund is created through the factory, we need to look for it differently
            $fundAddress = $null
            $fundTransaction = $null
            
            # Method 1: Look for WhackRockFund by contractName
            foreach ($tx in $broadcastContent.transactions) {
                if ($tx.contractName -eq "WhackRockFund") {
                    $fundAddress = $tx.contractAddress
                    $fundTransaction = $tx
                    Write-Host "Found WhackRockFund by contractName" -ForegroundColor Gray
                    break
                }
            }
            
            # Method 2: If not found, look for createWhackRockFund function call and extract return value
            if (-not $fundAddress) {
                foreach ($tx in $broadcastContent.transactions) {
                    if ($tx.function -and $tx.function -like "*createWhackRockFund*") {
                        Write-Host "Found createWhackRockFund function call" -ForegroundColor Gray
                        # The fund address should be in the logs or return value
                        if ($tx.contractAddress) {
                            $fundAddress = $tx.contractAddress
                            $fundTransaction = $tx
                            Write-Host "Found fund address from createWhackRockFund transaction" -ForegroundColor Gray
                            break
                        }
                    }
                }
            }
            
            # Method 3: Parse logs to find fund creation event
            if (-not $fundAddress) {
                Write-Host "Searching in transaction logs for fund creation..." -ForegroundColor Gray
                foreach ($tx in $broadcastContent.transactions) {
                    if ($tx.transaction -and $tx.transaction.logs) {
                        foreach ($log in $tx.transaction.logs) {
                            # Look for events that might contain the fund address
                            if ($log.topics -and $log.topics.Count -gt 0) {
                                # The fund address might be in the event data
                                Write-Host "Found transaction with logs, checking..." -ForegroundColor Gray
                            }
                        }
                    }
                }
            }
            
            # Method 4: Debug - show all transaction info
            if (-not $fundAddress) {
                Write-Host "Debug: Showing all transactions in broadcast file:" -ForegroundColor Yellow
                $txIndex = 0
                foreach ($tx in $broadcastContent.transactions) {
                    Write-Host "Transaction $txIndex:" -ForegroundColor Gray
                    Write-Host "  Contract Name: $($tx.contractName)" -ForegroundColor Gray
                    Write-Host "  Contract Address: $($tx.contractAddress)" -ForegroundColor Gray
                    Write-Host "  Function: $($tx.function)" -ForegroundColor Gray
                    Write-Host "  Transaction Type: $($tx.transactionType)" -ForegroundColor Gray
                    if ($tx.transaction) {
                        Write-Host "  To: $($tx.transaction.to)" -ForegroundColor Gray
                        Write-Host "  Input length: $($tx.transaction.data.Length)" -ForegroundColor Gray
                    }
                    $txIndex++
                }
            }
            
            if ($fundAddress) {
                Write-Host "Found WhackRockFund at address: $fundAddress" -ForegroundColor Green
                
                # Get deployer address from broadcast
                $deployerAddress = $broadcastContent.transactions[0].transaction.from
                Write-Host "Deployer address: $deployerAddress" -ForegroundColor Gray
                
                # Extract constructor arguments from the createWhackRockFund call
                $createFundTx = $null
                foreach ($tx in $broadcastContent.transactions) {
                    if ($tx.function -and $tx.function -like "*createWhackRockFund*") {
                        $createFundTx = $tx
                        break
                    }
                }
                
                if ($createFundTx -and $createFundTx.arguments) {
                    Write-Host "Found createWhackRockFund transaction, extracting constructor args..." -ForegroundColor Gray
                    
                    # The constructor args for WhackRockFund are passed from the factory
                    # We need to reconstruct them based on the createWhackRockFund call
                    $args = $createFundTx.arguments
                    
                    # WhackRockFund constructor parameters (from factory call):
                    # address _initialOwner,
                    # address _initialAgent,
                    # address _uniswapV3RouterAddress,
                    # address _uniswapV3QuoterAddress,
                    # address _uniswapV3FactoryAddress,
                    # address _wethAddress,
                    # address[] memory _fundAllowedTokens,
                    # uint256[] memory _initialTargetWeights,
                    # string memory _vaultName,
                    # string memory _vaultSymbol,
                    # string memory _vaultURI,
                    # address _agentAumFeeWalletForFund,
                    # uint256 _agentSetTotalAumFeeBps,
                    # address _protocolAumFeeRecipientForFunds,
                    # address _usdcTokenAddress,
                    # string memory data
                    
                    # Use forge to encode the constructor arguments
                    # Note: The createWhackRockFund call now includes fundDescription parameter
                    # createWhackRockFund params: _initialAgent, _fundAllowedTokens, _initialTargetWeights, _poolAddresses, _vaultName, _vaultSymbol, _vaultURI, _fundDescription, _agentAumFeeWalletForFund, _agentSetTotalAumFeeBps
                    
                    $encodeArgs = @(
                        "abi-encode",
                        "constructor(address,address,address,address,address,address,address[],uint256[],string,string,string,address,uint256,address,address,string)",
                        $deployerAddress,  # _initialOwner
                        $args[0],         # _initialAgent (from createWhackRockFund call)
                        "0x2626664c2603336E57B271c5C0b26F421741e481", # uniswapV3Router
                        "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a", # uniswapV3Quoter
                        "0x33128a8fC17869897dcE68Ed026d694621f6FDfD", # uniswapV3Factory
                        "0x4200000000000000000000000000000000000006", # WETH
                        "[$($args[1] -join ',')]", # _fundAllowedTokens array (3 tokens: USDC, cbBTC, VIRTUAL)
                        "[$($args[2] -join ',')]", # _initialTargetWeights array (4000, 5000, 1000)
                        "`"$($args[4])`"",        # _vaultName ("BenFan Fund by WhackRock")
                        "`"$($args[5])`"",        # _vaultSymbol ("BFWRF")
                        "`"$($args[6])`"",        # _vaultURI ("https://x.com/benjAImin_agent")
                        $args[8],                 # _agentAumFeeWalletForFund (deployerAddress)
                        $args[9],                 # _agentSetTotalAumFeeBps (200)
                        "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae", # protocolAumFeeRecipient
                        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", # USDC
                        "`"`""                    # empty data string
                    )
                    
                    Write-Host "Encoding constructor arguments..." -ForegroundColor Gray
                    $constructorArgsResult = & $forgeExecutable $encodeArgs 2>&1
                    
                    if ($LASTEXITCODE -eq 0 -and $constructorArgsResult) {
                        $constructorArgs = $constructorArgsResult.Trim() -replace "^0x", ""
                        Write-Host "Constructor args encoded successfully" -ForegroundColor Green
                    } else {
                        Write-Host "Failed to encode constructor args, using fallback method" -ForegroundColor Yellow
                        # Fallback: construct manually based on deployment script values
                        $constructorArgs = "000000000000000000000000$($deployerAddress.Substring(2))" + 
                                          "000000000000000000000000$($deployerAddress.Substring(2))" +
                                          "0000000000000000000000002626664c2603336e57b271c5c0b26f421741e481" +
                                          "0000000000000000000000003d4e44eb1374240ce5f1b871ab261cd16335b76a" +
                                          "00000000000000000000000033128a8fc17869897dce68ed026d694621f6fdfd" +
                                          "0000000000000000000000004200000000000000000000000000000000000006"
                        # Add more encoded args as needed...
                    }
                } else {
                    Write-Host "Could not extract constructor arguments from broadcast file" -ForegroundColor Yellow
                    Write-Host "Using default constructor args based on deployment script" -ForegroundColor Gray
                    
                    # Use hardcoded values from the deployment script
                    # BenFan Fund with 3 tokens: USDC(40%), cbBTC(50%), VIRTUAL(10%)
                    # Fund name: "BenFan Fund by WhackRock", symbol: "BFWRF"
                    
                    # Use forge to encode with known values from deployment script
                    $fallbackEncodeArgs = @(
                        "abi-encode",
                        "constructor(address,address,address,address,address,address,address[],uint256[],string,string,string,address,uint256,address,address,string)",
                        $deployerAddress,  # _initialOwner
                        $deployerAddress,  # _initialAgent
                        "0x2626664c2603336E57B271c5C0b26F421741e481", # uniswapV3Router
                        "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a", # uniswapV3Quoter
                        "0x33128a8fC17869897dcE68Ed026d694621f6FDfD", # uniswapV3Factory
                        "0x4200000000000000000000000000000000000006", # WETH
                        "[0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,0x0b3e328455c4059EEb9e3f84b5543F74e24e7E1b]", # 3 tokens: USDC, cbBTC, VIRTUAL
                        "[4000,5000,1000]", # weights: 40%, 50%, 10%
                        "`"BenFan Fund by WhackRock`"", # fund name
                        "`"BFWRF`"",                    # fund symbol
                        "`"https://x.com/benjAImin_agent`"", # fund URI
                        $deployerAddress,  # _agentAumFeeWalletForFund
                        "200",            # _agentSetTotalAumFeeBps (2%)
                        "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae", # protocolAumFeeRecipient
                        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", # USDC
                        "`"`""           # empty data string
                    )
                    
                    Write-Host "Encoding fallback constructor arguments..." -ForegroundColor Gray
                    $fallbackResult = & $forgeExecutable $fallbackEncodeArgs 2>&1
                    
                    if ($LASTEXITCODE -eq 0 -and $fallbackResult) {
                        $constructorArgs = $fallbackResult.Trim() -replace "^0x", ""
                        Write-Host "Fallback constructor args encoded successfully" -ForegroundColor Green
                    } else {
                        Write-Host "Failed to encode fallback constructor args, using minimal fallback" -ForegroundColor Yellow
                        # Very basic fallback with just the addresses
                        $constructorArgs = "000000000000000000000000$($deployerAddress.Substring(2).ToLower())" +
                                          "000000000000000000000000$($deployerAddress.Substring(2).ToLower())" +
                                          "0000000000000000000000002626664c2603336e57b271c5c0b26f421741e481" +
                                          "0000000000000000000000003d4e44eb1374240ce5f1b871ab261cd16335b76a" +
                                          "00000000000000000000000033128a8fc17869897dce68ed026d694621f6fdfd" +
                                          "0000000000000000000000004200000000000000000000000000000000000006"
                    }
                }
                
                Write-Host "Attempting to verify WhackRockFund..." -ForegroundColor Yellow
                
                # Run forge verify-contract command for the UniSwap TWAP version
                $verifyArgs = @(
                    "verify-contract",
                    $fundAddress,
                    "src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund",
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
                    Write-Host "Fund Address: $fundAddress" -ForegroundColor Gray
                    Write-Host "Manual verification command:" -ForegroundColor Gray
                    Write-Host "forge verify-contract $fundAddress src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund --chain 8453 --constructor-args 0x$constructorArgs --etherscan-api-key <YOUR_API_KEY>" -ForegroundColor Gray
                }
                
            } else {
                Write-Host "Could not find WhackRockFund address in broadcast file." -ForegroundColor Yellow
                
                # Method 5: Try to extract from recent forge output/logs
                Write-Host "Attempting to find fund address from forge output..." -ForegroundColor Gray
                
                # Look for recent forge broadcast logs that might contain the fund address
                $logFiles = Get-ChildItem -Path "broadcast" -Recurse -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 5
                
                foreach ($logFile in $logFiles) {
                    try {
                        $logContent = Get-Content $logFile.FullName -Raw | ConvertFrom-Json
                        if ($logContent.transactions) {
                            foreach ($tx in $logContent.transactions) {
                                if ($tx.contractName -eq "WhackRockFund" -and $tx.contractAddress) {
                                    $fundAddress = $tx.contractAddress
                                    Write-Host "Found WhackRockFund in $($logFile.Name): $fundAddress" -ForegroundColor Green
                                    break
                                }
                            }
                        }
                        if ($fundAddress) { break }
                    } catch {
                        # Skip invalid JSON files
                    }
                }
                
                if ($fundAddress) {
                    Write-Host "Found fund address from logs: $fundAddress" -ForegroundColor Green
                    
                    # Get deployer address from the main broadcast file
                    $deployerAddress = $broadcastContent.transactions[0].transaction.from
                    Write-Host "Deployer address: $deployerAddress" -ForegroundColor Gray
                    
                    # Use the fallback method with known deployment values
                    Write-Host "Using fallback constructor arguments for fund verification..." -ForegroundColor Gray
                    
                    $fallbackEncodeArgs = @(
                        "abi-encode",
                        "constructor(address,address,address,address,address,address,address[],uint256[],string,string,string,address,uint256,address,address,string)",
                        $deployerAddress,  # _initialOwner
                        $deployerAddress,  # _initialAgent
                        "0x2626664c2603336E57B271c5C0b26F421741e481", # uniswapV3Router
                        "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a", # uniswapV3Quoter
                        "0x33128a8fC17869897dcE68Ed026d694621f6FDfD", # uniswapV3Factory
                        "0x4200000000000000000000000000000000000006", # WETH
                        "[0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,0x0b3e328455c4059EEb9e3f84b5543F74e24e7E1b]", # 3 tokens
                        "[4000,5000,1000]", # weights
                        "`"BenFan Fund by WhackRock`"", # fund name
                        "`"BFWRF`"",                    # fund symbol
                        "`"https://x.com/benjAImin_agent`"", # fund URI
                        $deployerAddress,  # _agentAumFeeWalletForFund
                        "200",            # _agentSetTotalAumFeeBps
                        "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae", # protocolAumFeeRecipient
                        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", # USDC
                        "`"`""           # empty data string
                    )
                    
                    $constructorArgsResult = & $forgeExecutable $fallbackEncodeArgs 2>&1
                    
                    if ($LASTEXITCODE -eq 0 -and $constructorArgsResult) {
                        $constructorArgs = $constructorArgsResult.Trim() -replace "^0x", ""
                        
                        Write-Host "Attempting to verify WhackRockFund with fallback args..." -ForegroundColor Yellow
                        
                        $verifyArgs = @(
                            "verify-contract",
                            $fundAddress,
                            "src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund",
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
                            Write-Host "WhackRockFund verification failed." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "Failed to encode constructor arguments for fallback verification." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Could not find WhackRockFund address in any broadcast files." -ForegroundColor Yellow
                    Write-Host "Please check the deployment logs for a line like: 'Dummy WhackRockFund created at: 0x...'" -ForegroundColor Gray
                    
                    # Ask user if they want to manually provide the fund address
                    $manualAddress = Read-Host "Would you like to manually enter the fund address for verification? (Enter address or 'n' to skip)"
                    
                    if ($manualAddress -and $manualAddress -ne 'n' -and $manualAddress -match '^0x[a-fA-F0-9]{40}$') {
                        Write-Host "Using manually provided fund address: $manualAddress" -ForegroundColor Green
                        
                        # Get deployer address from the main broadcast file
                        $deployerAddress = $broadcastContent.transactions[0].transaction.from
                        Write-Host "Deployer address: $deployerAddress" -ForegroundColor Gray
                        
                        # Use the fallback method with known deployment values
                        Write-Host "Encoding constructor arguments for manual verification..." -ForegroundColor Gray
                        
                        $manualEncodeArgs = @(
                            "abi-encode",
                            "constructor(address,address,address,address,address,address,address[],uint256[],string,string,string,address,uint256,address,address,string)",
                            $deployerAddress,  # _initialOwner
                            $deployerAddress,  # _initialAgent
                            "0x2626664c2603336E57B271c5C0b26F421741e481", # uniswapV3Router
                            "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a", # uniswapV3Quoter
                            "0x33128a8fC17869897dcE68Ed026d694621f6FDfD", # uniswapV3Factory
                            "0x4200000000000000000000000000000000000006", # WETH
                            "[0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,0x0b3e328455c4059EEb9e3f84b5543F74e24e7E1b]", # 3 tokens
                            "[4000,5000,1000]", # weights
                            "`"BenFan Fund by WhackRock`"", # fund name
                            "`"BFWRF`"",                    # fund symbol
                            "`"https://x.com/benjAImin_agent`"", # fund URI
                            $deployerAddress,  # _agentAumFeeWalletForFund
                            "200",            # _agentSetTotalAumFeeBps
                            "0x90cfB07A46EE4bb20C970Dda18AaD1BA3c9450Ae", # protocolAumFeeRecipient
                            "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", # USDC
                            "`"`""           # empty data string
                        )
                        
                        $manualConstructorResult = & $forgeExecutable $manualEncodeArgs 2>&1
                        
                        if ($LASTEXITCODE -eq 0 -and $manualConstructorResult) {
                            $manualConstructorArgs = $manualConstructorResult.Trim() -replace "^0x", ""
                            
                            Write-Host "Attempting to verify manually provided WhackRockFund address..." -ForegroundColor Yellow
                            
                            $manualVerifyArgs = @(
                                "verify-contract",
                                $manualAddress,
                                "src/WhackRockFundV6_UniSwap_TWAP.sol:WhackRockFund",
                                "--chain", "8453",
                                "--etherscan-api-key", $actualBasescanApiKey,
                                "--constructor-args", "0x$manualConstructorArgs",
                                "--watch"
                            )
                            
                            Write-Host "Executing: $forgeExecutable $($manualVerifyArgs -join ' ')"
                            & $forgeExecutable $manualVerifyArgs
                            
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "WhackRockFund verification submitted successfully!" -ForegroundColor Green
                            } else {
                                Write-Host "WhackRockFund verification failed. Please check the logs." -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "Failed to encode constructor arguments for manual verification." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "Skipping manual fund verification." -ForegroundColor Gray
                    }
                }
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