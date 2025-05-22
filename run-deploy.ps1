# Load environment variables from .env file
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Item -Path "Env:$name" -Value $value
    }
}

# Display info about the deployment
Write-Host "=== WhackRock Treasury Deployment to Base ===" -ForegroundColor Green
Write-Host "Loading environment from .env file"
Write-Host "USDC Address: $env:USDC_ADDRESS"
Write-Host "WETH Address: $env:WETH_ADDRESS"
Write-Host ""

# Ask for confirmation
$confirmation = Read-Host "Continue with deployment? (y/n)"
if ($confirmation -ne 'y') {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 1
}

# Run the forge command
Write-Host "Running forge script..." -ForegroundColor Cyan
forge script script/DeployToBase.s.sol:DeployToBaseScript `
    --rpc-url $env:RPC_URL `
    --broadcast `
    --verify `
    --etherscan-api-key $env:BASESCAN_API_KEY `
    -vvv

# Check if deployment was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Contract addresses have been displayed in the logs above." -ForegroundColor Green
    Write-Host "IMPORTANT: Make sure to record these addresses manually!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You can now create custom vaults using the factory contract." -ForegroundColor Cyan
} else {
    Write-Host "Deployment failed. Check the logs for errors." -ForegroundColor Red
} 