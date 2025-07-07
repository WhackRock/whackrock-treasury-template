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
$scriptName = "UpdateProtocolCreationFee" # Solidity script contract name
$scriptFile = "script/$($scriptName).s.sol" # Path to your script
$newFeeAmount = "170 USDC" # Human readable fee amount

# --- REGISTRY UPDATE --- 
Write-Host "=== WhackRock Fund Registry Protocol Fee Update on Base ===" -ForegroundColor Green
Write-Host "Loading environment from .env file..."
Write-Host "RPC URL: $($env:RPC_URL)"
Write-Host "Basescan API Key: $($env:BASESCAN_API_KEY -replace '.{20}$', '...')"
Write-Host ""

# Show what we're about to do
Write-Host "=== Update Details ===" -ForegroundColor Yellow
Write-Host "Script: $scriptFile"
Write-Host "New Protocol Creation Fee: $newFeeAmount"
Write-Host "Target Network: Base Mainnet (Chain ID: 8453)"
Write-Host ""

# Ask for confirmation
$confirmation = Read-Host "Continue with PROTOCOL FEE UPDATE? This will change the fund creation fee to $newFeeAmount (y/n)"
if ($confirmation -ne 'y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 1
}

Write-Host "Running forge script for protocol fee update..." -ForegroundColor Cyan

# Construct arguments for forge command
$forgeExecutable = "forge" # Assumes forge is in PATH
$scriptPathWithContract = "${scriptFile}:$($scriptName)"
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

# Capture the output to extract relevant information
$scriptOutput = & $forgeExecutable $forgeCommandArgs 2>&1 | Tee-Object -Variable outputLines
$scriptOutput | ForEach-Object { Write-Host $_ }

# Check if the update was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Protocol Fee Update submitted successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "The registry parameter update has been broadcast to Base network."
    Write-Host "Transaction details are saved to the broadcast files." -ForegroundColor Yellow
    Write-Host "Broadcast file: broadcast/$($scriptName).s.sol/8453/run-latest.json" -ForegroundColor Yellow
    
    # Extract registry address and fee info from output
    $registryAddress = $null
    $currentFee = $null
    $newFee = $null
    
    foreach ($line in $outputLines) {
        if ($line -match "Registry Proxy Address:\s*(0x[a-fA-F0-9]{40})") {
            $registryAddress = $matches[1]
            Write-Host "Registry Address: $registryAddress" -ForegroundColor Green
        }
        elseif ($line -match "Current Protocol Creation Fee:\s*([0-9]+)") {
            $currentFee = $matches[1]
        }
        elseif ($line -match "New Protocol Creation Fee:\s*([0-9]+)") {
            $newFee = $matches[1]
        }
    }
    
    Write-Host ""
    Write-Host "=== Update Summary ===" -ForegroundColor Cyan
    if ($registryAddress) {
        Write-Host "WhackRock Fund Registry: $registryAddress" -ForegroundColor Green
        Write-Host "Basescan: https://basescan.org/address/$registryAddress" -ForegroundColor Cyan
    }
    if ($currentFee -and $newFee) {
        Write-Host "Previous Fee: $currentFee wei" -ForegroundColor Yellow
        Write-Host "New Fee: $newFee wei ($newFeeAmount)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== Verification ===" -ForegroundColor Yellow
    Write-Host "To verify the update was successful, you can:"
    Write-Host "1. Check the transaction on Basescan"
    Write-Host "2. Query the registry contract's protocolFundCreationFeeUsdcAmount() function"
    Write-Host "3. The new fee should be: 170000000 (170 USDC with 6 decimals)"
    Write-Host ""
    
    Write-Host "=== Next Steps ===" -ForegroundColor Yellow
    Write-Host "- The protocol creation fee is now set to $newFeeAmount"
    Write-Host "- New fund creators will need to pay this fee in USDC"
    Write-Host "- The fee is collected by the WhackRock rewards address"
    Write-Host "- Fund creation will fail if users don't have sufficient USDC balance"
    Write-Host ""
    
} else {
    Write-Host "Protocol Fee Update failed. Check the logs for errors." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "- Insufficient gas or gas price too low" -ForegroundColor Gray
    Write-Host "- Network connectivity issues" -ForegroundColor Gray
    Write-Host "- Invalid private key or RPC URL" -ForegroundColor Gray
    Write-Host "- Not the owner of the registry contract" -ForegroundColor Gray
    Write-Host "- Registry proxy address not set correctly in script" -ForegroundColor Gray
    Write-Host "- Contract compilation errors" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Important Notes ===" -ForegroundColor Cyan
Write-Host "- Only the registry owner can update protocol parameters"
Write-Host "- The update affects all future fund creations immediately"
Write-Host "- Make sure to update the REGISTRY_PROXY_ADDRESS in the script before running"
Write-Host "- The fee is denominated in USDC (6 decimals)"
Write-Host ""