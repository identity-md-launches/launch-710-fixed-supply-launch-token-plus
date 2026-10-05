// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

contract LaunchTokenHandler is Test {
    uint256 public constant SUPPLY = 10 ** 27;
    LaunchToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new LaunchToken();
        actors = [address(this), address(0xA001), address(0xA002), address(0xA003)];
        // Every token stays inside this actor set. No deal/store cheatcodes fund the token.
        for (uint256 i; i < actors.length; ++i) {
            if (i != 0) assertTrue(token.transfer(actors[i], SUPPLY / 4));
            expectedBalance[actors[i]] = SUPPLY / 4;
        }
        // Seed finite and infinite approvals so delegated transfers are reachable immediately.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % 4], SUPPLY / 8);
            _approve(actors[i], actors[(i + 2) % 4], type(uint256).max);
        }
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 rawAmount, uint8 mode) external {
        // Include revocations, infinite approvals, and finite approvals below and above supply.
        uint256 amount = mode % 4 == 0
            ? 0
            : mode % 4 == 1 ? type(uint256).max : mode % 4 == 2 ? bound(rawAmount, 0, SUPPLY) : rawAmount;
        _approve(actors[ownerSeed % 4], actors[spenderSeed % 4], amount);
    }

    function transferFrom(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from] < allowance ? expectedBalance[from] : allowance;
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) expectedAllowance[from][spender] -= amount;
    }

    function transferTooMuch(uint8 fromSeed, uint8 toSeed, uint256 rawExcess) external {
        address from = actors[fromSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(rawExcess, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(actors[toSeed % 4], amount);
        // Leave the model unchanged: invariants also check rollback for every other actor.
    }

    function transferFromTooMuch(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = (balance < allowance ? balance : allowance) + 1;
        if (allowance < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        vm.prank(spender);
        token.transferFrom(from, actors[toSeed % 4], amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    LaunchTokenHandler private handler;
    LaunchToken private token;

    function setUp() public {
        handler = new LaunchTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferTooMuch.selector;
        selectors[4] = handler.transferFromTooMuch.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyAndExactBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor), "unexpected balance change");
            sum += balance;
        }
        assertEq(sum, 10 ** 27, "tokens lost or created");
        assertEq(token.totalSupply(), 10 ** 27, "supply changed");
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function test_handlerExercisesNonzeroSpendingRevocationAndFailures() public {
        address owner = handler.actors(0);
        address spender = handler.actors(1);
        handler.transfer(0, 1, 1);
        handler.transferFrom(0, 1, 2, 2);
        assertEq(token.balanceOf(owner), 10 ** 27 / 4 - 3);
        assertEq(token.allowance(owner, spender), 10 ** 27 / 8 - 2);
        handler.approve(0, 1, 0, 0);
        handler.transferFromTooMuch(0, 1, 2);
        handler.transferTooMuch(0, 1, 1);
        invariant_fixedSupplyAndExactBalances();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
    }
}
