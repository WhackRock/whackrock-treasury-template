// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/interfaces/ISwapAdapter.sol";

contract MockSwapAdapter is ISwapAdapter {
    bytes public lastExecuteData;
    
    function execute(bytes calldata data) 
        external 
        payable 
        override 
        returns (bool success) 
    {
        lastExecuteData = data;
        return true; // Always succeed for testing
    }
} 