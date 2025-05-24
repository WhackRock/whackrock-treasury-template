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
} else {
    Write-Host "Deployment or Verification submission failed. Check the logs for errors." -ForegroundColor Red
}