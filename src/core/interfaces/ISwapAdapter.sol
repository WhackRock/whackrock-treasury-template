// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 WhackRock Labs. All rights reserved.
pragma solidity ^0.8.20;

/**
 * @title ISwapAdapter
 * @notice Router‑agnostic interface.  A vault passes arbitrary calldata
 *         (e.g. Universal Router) and expects true on success or revert.
 */
interface ISwapAdapter {
    /// @param data   ABI‑encoded call to the underlying router
    /// @return success  MUST return true (or revert) if swaps succeeded
    function execute(bytes calldata data)
        external
        payable
        returns (bool success);
}
