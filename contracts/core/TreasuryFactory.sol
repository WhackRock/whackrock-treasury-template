// SPDX‑License‑Identifier: BUSL‑1.1
pragma solidity ^0.8.25;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { WeightedTreasuryVault } from "./WeightedTreasuryVault.sol";
import "./interfaces/ISwapAdapter.sol";
import "./interfaces/IPriceOracle.sol";

contract TreasuryFactory {
    event VaultCreated(address vault, address manager, bytes32 tag);

    address public immutable logic;        // WeightedTreasuryVault impl
    ISwapAdapter public immutable adapter;
    IPriceOracle public immutable oracle;
    address public immutable wrkRewards;   // global 20 % sink

    constructor(
        address _logic,
        ISwapAdapter _adapter,
        IPriceOracle _oracle,
        address _wrkRewards
    ) {
        logic       = _logic;
        adapter     = _adapter;
        oracle      = _oracle;
        wrkRewards  = _wrkRewards;
    }

    /**
     * @param mgmtFeeBps  e.g. 200 = 2 % upfront fee
     * @param devWallet   receives 80 % of that fee
     * @param tag         "AGENT" or "FUND" – for indexers/front‑end
     */
    function createVault(
        string   calldata name,
        string   calldata sym,
        address[] calldata assets,
        uint256[] calldata initW,
        address manager,
        uint16   mgmtFeeBps,
        address  devWallet,
        bytes32  tag
    ) external returns (address vault) {
        bytes32 salt = keccak256(abi.encodePacked(manager, name));
        vault = Clones.cloneDeterministic(logic, salt);

        WeightedTreasuryVault(vault).initialize(
            name,
            sym,
            toIERC20(assets),
            initW,
            manager,
            adapter,
            oracle,
            mgmtFeeBps,
            devWallet,
            wrkRewards
        );
        emit VaultCreated(vault, manager, tag);
    }

    /* cast memory array of addresses to IERC20[] without copy */
    function toIERC20(address[] calldata addrs)
        internal pure returns (IERC20[] memory out)
    {
        assembly { out := addrs.offset }
    }

    function predict(address manager, string calldata name)
        external view returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(manager, name));
        return Clones.predictDeterministicAddress(logic, salt, address(this));
    }
}
