// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Plain ERC-20 with its entire, permanent supply minted to the deployer.
contract LaunchToken is ERC20 {
    constructor() ERC20("Guestbook", "GUEST") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
