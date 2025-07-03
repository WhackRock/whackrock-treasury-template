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
$deploymentScriptName = "DeployStaking" # Solidity script contract name
$deploymentScriptFile = "script/$($deploymentScriptName).s.sol" # Path to your deployment script

# --- DEPLOYMENT & VERIFICATION --- 
Write-Host "=== WROCK Staking Deployment & Verification to Base ===" -ForegroundColor Green
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

# Capture the output to extract contract addresses
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
    
    # Extract contract addresses from output
    $stakingAddress = $null
    $redeemerAddress = $null
    
    foreach ($line in $outputLines) {
        if ($line -match "WROCKStaking deployed at:\s*(0x[a-fA-F0-9]{40})") {
            $stakingAddress = $matches[1]
            Write-Host "Found WROCKStaking address: $stakingAddress" -ForegroundColor Green
        }
        elseif ($line -match "PointsRedeemer deployed at:\s*(0x[a-fA-F0-9]{40})") {
            $redeemerAddress = $matches[1]
            Write-Host "Found PointsRedeemer address: $redeemerAddress" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    Write-Host "=== Contract Summary ===" -ForegroundColor Cyan
    if ($stakingAddress) {
        Write-Host "WROCKStaking: $stakingAddress" -ForegroundColor Green
        Write-Host "Basescan: https://basescan.org/address/$stakingAddress" -ForegroundColor Cyan
    }
    if ($redeemerAddress) {
        Write-Host "PointsRedeemer: $redeemerAddress" -ForegroundColor Green
        Write-Host "Basescan: https://basescan.org/address/$redeemerAddress" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "=== Manual Verification (if needed) ===" -ForegroundColor Yellow
    Write-Host "If automatic verification fails, use these commands:"
    Write-Host ""
    
    if ($stakingAddress) {
        Write-Host "WROCKStaking verification:" -ForegroundColor Cyan
        Write-Host "forge verify-contract $stakingAddress src/staking/WROCKStaking.sol:WROCKStaking --chain 8453 --constructor-args \$(cast abi-encode \"constructor(address)\" \"0x2626664c2603336E57B271c5C0b26F421741e481\") --etherscan-api-key $($env:BASESCAN_API_KEY)" -ForegroundColor Gray
        Write-Host ""
    }
    
    if ($redeemerAddress -and $stakingAddress) {
        Write-Host "PointsRedeemer verification:" -ForegroundColor Cyan
        Write-Host "forge verify-contract $redeemerAddress src/staking/PointsRedeemer.sol:PointsRedeemer --chain 8453 --constructor-args \$(cast abi-encode \"constructor(address)\" \"$stakingAddress\") --etherscan-api-key $($env:BASESCAN_API_KEY)" -ForegroundColor Gray
        Write-Host ""
    }
    
    Write-Host "=== Configuration Steps ===" -ForegroundColor Yellow
    Write-Host "After deployment, you need to:"
    Write-Host "1. Wait 48 hours for timelock delay"
    Write-Host "2. Execute the queued setPointsRedeemer operation on WROCKStaking"
    Write-Host "3. Set reward token in PointsRedeemer contract"
    Write-Host "4. Deposit reward tokens to PointsRedeemer"
    Write-Host "5. Enable redemption when ready"
    Write-Host ""
    
} else {
    Write-Host "Deployment or Verification submission failed. Check the logs for errors." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "- Insufficient gas or gas price too low" -ForegroundColor Gray
    Write-Host "- Network connectivity issues" -ForegroundColor Gray
    Write-Host "- Invalid private key or RPC URL" -ForegroundColor Gray
    Write-Host "- Contract compilation errors" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Important Notes ===" -ForegroundColor Cyan
Write-Host "- The WROCKStaking contract uses a 48-hour timelock for admin functions"
Write-Host "- Both contracts have pausable functionality for emergencies"
Write-Host "- All token transfers use SafeERC20 for security"
Write-Host "- ReentrancyGuard is implemented on all external functions"
Write-Host "- Update the WROCK_TOKEN address in the script if needed"
Write-Host ""