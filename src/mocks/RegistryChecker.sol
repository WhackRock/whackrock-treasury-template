// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RemixRegistryChecker
 * @notice Simple interface for checking WhackRock Fund Registry parameters in Remix
 * @dev Use this interface to interact with the deployed WhackRockFundRegistry contract
 */
interface IWhackRockFundRegistryChecker {
    // Public variables from the registry contract
    function protocolFundCreationFeeUsdcAmount() external view returns (uint256);
    function whackRockRewardsAddress() external view returns (address);
    function totalAumFeeBpsForFunds() external view returns (uint256);
    function protocolAumFeeRecipientForFunds() external view returns (address);
    function maxAgentDepositFeeBps() external view returns (uint256);
    function maxInitialAllowedTokensLength() external view returns (uint256);
    function fundCounter() external view returns (uint256);
    function USDC_TOKEN() external view returns (address);
    function WETH_ADDRESS() external view returns (address);
    
    // Useful getter functions
    function getDeployedFundsCount() external view returns (uint256);
    function getFundAddressByIndex(uint256 _index) external view returns (address);
    function getRegistryAllowedTokens() external view returns (address[] memory);
    function isTokenAllowedInRegistry(address _token) external view returns (bool);
    function isSymbolTaken(string memory _symbol) external view returns (bool);
    function fundToCreator(address _fund) external view returns (address);
    function deployedFunds(uint256 _index) external view returns (address);
    function allowedTokensList(uint256 _index) external view returns (address);
    
    // Owner function (for checking ownership)
    function owner() external view returns (address);
}

/**
 * @title RegistryChecker
 * @notice Helper contract to check registry parameters
 * @dev Deploy this contract or use it as a library to check registry state
 */
contract RegistryChecker {
    IWhackRockFundRegistryChecker public registry;
    
    constructor(address _registryAddress) {
        registry = IWhackRockFundRegistryChecker(_registryAddress);
    }
    
    /**
     * @notice Get the current protocol creation fee in USDC wei (6 decimals)
     * @return Current protocol creation fee amount
     */
    function getCurrentProtocolCreationFee() external view returns (uint256) {
        return registry.protocolFundCreationFeeUsdcAmount();
    }
    
    /**
     * @notice Get the protocol creation fee in human-readable format
     * @return Human-readable fee amount (assuming 6 decimals for USDC)
     */
    function getProtocolCreationFeeInUSDC() external view returns (string memory) {
        uint256 feeWei = registry.protocolFundCreationFeeUsdcAmount();
        if (feeWei == 0) {
            return "0 USDC";
        }
        
        uint256 dollars = feeWei / 1e6;
        uint256 cents = (feeWei % 1e6) / 1e4;
        
        if (cents == 0) {
            return string(abi.encodePacked(toString(dollars), " USDC"));
        } else {
            return string(abi.encodePacked(toString(dollars), ".", toString(cents), " USDC"));
        }
    }
    
    /**
     * @notice Get all key registry parameters
     * @return protocolFee Current protocol creation fee in wei
     * @return usdcToken Address of USDC token
     * @return rewardsAddr Address that receives protocol fees
     * @return totalFunds Total number of funds created
     * @return registryOwner Address of the registry owner
     */
    function getRegistryInfo() external view returns (
        uint256 protocolFee,
        address usdcToken,
        address rewardsAddr,
        uint256 totalFunds,
        address registryOwner
    ) {
        protocolFee = registry.protocolFundCreationFeeUsdcAmount();
        usdcToken = registry.USDC_TOKEN();
        rewardsAddr = registry.whackRockRewardsAddress();
        totalFunds = registry.fundCounter();
        registryOwner = registry.owner();
    }
    
    /**
     * @notice Check if the protocol creation fee is set to 170 USDC
     * @return True if fee is exactly 170 USDC (170000000 wei)
     */
    function isProtocolFee170USDC() external view returns (bool) {
        return registry.protocolFundCreationFeeUsdcAmount() == 170 * 1e6;
    }
    
    /**
     * @notice Get the number of allowed tokens in the registry
     * @return Number of allowed tokens
     */
    function getAllowedTokensCount() external view returns (uint256) {
        return registry.getRegistryAllowedTokens().length;
    }
    
    // Helper function to convert uint to string
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

/**
 * @title QuickRegistryChecker
 * @notice Minimal contract for quick registry checks
 * @dev Use this for simple one-off checks without deploying the full checker
 */
contract QuickRegistryChecker {
    /**
     * @notice Check protocol creation fee for any registry
     * @param _registryAddress Address of the WhackRockFundRegistry
     * @return Current protocol creation fee in wei
     */
    function checkProtocolCreationFee(address _registryAddress) external view returns (uint256) {
        IWhackRockFundRegistryChecker registry = IWhackRockFundRegistryChecker(_registryAddress);
        return registry.protocolFundCreationFeeUsdcAmount();
    }
    
    /**
     * @notice Check if fee is set to 170 USDC
     * @param _registryAddress Address of the WhackRockFundRegistry
     * @return True if fee is exactly 170 USDC
     */
    function isProtocolFee170USDC(address _registryAddress) external view returns (bool) {
        IWhackRockFundRegistryChecker registry = IWhackRockFundRegistryChecker(_registryAddress);
        return registry.protocolFundCreationFeeUsdcAmount() == 170 * 1e6;
    }
    
    /**
     * @notice Get basic registry info
     * @param _registryAddress Address of the WhackRockFundRegistry
     * @return protocolFee Current protocol creation fee
     * @return totalFunds Total number of funds created
     * @return registryOwner Address of the registry owner
     */
    function getBasicRegistryInfo(address _registryAddress) external view returns (
        uint256 protocolFee,
        uint256 totalFunds,
        address registryOwner
    ) {
        IWhackRockFundRegistryChecker registry = IWhackRockFundRegistryChecker(_registryAddress);
        protocolFee = registry.protocolFundCreationFeeUsdcAmount();
        totalFunds = registry.fundCounter();
        registryOwner = registry.owner();
    }
}