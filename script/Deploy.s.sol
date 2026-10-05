// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {Guestbook} from "../src/Guestbook.sol";

/// @notice Standalone operator simulations. The network launch uses ProjectFactory instead.
/// @dev Each entry point records exactly one deployment and never reads wallet secrets.
contract Deploy is Script {
    error UnsupportedChain(uint256 chainId);
    error UnexpectedChain(uint256 expected, uint256 actual);

    function run() external returns (LaunchToken token) {
        checkChain(vm.envOr("EXPECTED_CHAIN_ID", uint256(0)));
        vm.startBroadcast();
        token = new LaunchToken();
        vm.stopBroadcast();
    }

    function runGuestbook(address initialOwner) external returns (Guestbook guestbook) {
        checkChain(vm.envOr("EXPECTED_CHAIN_ID", uint256(0)));
        vm.startBroadcast();
        guestbook = new Guestbook(initialOwner);
        vm.stopBroadcast();
    }

    /// @notice Zero only bypasses the expected-ID comparison on the local development chain.
    /// @dev Explicit input permits isolated tests without reading or changing the environment.
    function checkChain(uint256 expected) public view {
        uint256 actual = block.chainid;
        if (actual != 31337 && actual != 11155111) revert UnsupportedChain(actual);
        if (expected != actual && !(expected == 0 && actual == 31337)) {
            revert UnexpectedChain(expected, actual);
        }
    }
}
