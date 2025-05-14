// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

import { ISwapAdapter } from "../interfaces/ISwapAdapter.sol";

/**
 * @title UniAdapter
 * @dev Forwards raw Universal Router calldata. The vault pre‑approves
 *      its tokens to this adapter once; the adapter uses Permit2 under
 *      the hood when Universal Router executes.
 *
 *      Slippage checks live inside the calldata (minOut, deadline).
 */
contract UniAdapter is ISwapAdapter {
    address public immutable universalRouter;   // e.g. 0x3fC9… for Base

    constructor(address _router) {
        universalRouter = _router;
    }

    /// @inheritdoc ISwapAdapter
    function execute(bytes calldata data)
        external payable override returns (bool)
    {
        (bool ok, bytes memory returndata) =
            universalRouter.call{value: msg.value}(data);
        if (!ok) revert(string(returndata));
        return true;
    }
}
