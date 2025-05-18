// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

contract Counter {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
