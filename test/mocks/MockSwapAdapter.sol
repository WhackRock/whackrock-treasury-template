// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/interfaces/ISwapAdapter.sol";

contract MockSwapAdapter is ISwapAdapter {
    function execute(bytes calldata data) 
        external 
        payable 
        override 
        returns (bool success) 
    {
        return true; // Always succeed for testing
    }
} 