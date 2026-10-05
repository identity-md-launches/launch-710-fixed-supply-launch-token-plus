// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken private token;
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndWholeSupplyToDeployer() public view {
        assertEq(token.name(), "Guestbook");
        assertEq(token.symbol(), "GUEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferMovesExactAmountAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 5 ether);
        assertTrue(token.transfer(ALICE, 5 ether));
        assertEq(token.balanceOf(ALICE), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAndSelfTransfersPreserveBalances() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertTrue(token.transfer(ALICE, 0));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_cannotTransferMoreThanBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_cannotTransferOrApproveZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalAndTransferFromConsumeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), ALICE, 100);
        assertTrue(token.approve(ALICE, 100));
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 40));
        assertEq(token.allowance(address(this), ALICE), 60);
        assertEq(token.balanceOf(BOB), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromWithoutEnoughAllowanceReverts() public {
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 10, 11));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 11);
        assertEq(token.allowance(address(this), ALICE), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_failedTransferFromDoesNotConsumeAllowance() public {
        vm.prank(ALICE);
        token.approve(BOB, 20);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, BOB), 20);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_infiniteAllowanceUsesStandardSemantics() public {
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 10);
        assertEq(token.allowance(address(this), ALICE), type(uint256).max);
        assertEq(token.balanceOf(BOB), 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revokedAllowancePreventsSpending() public {
        token.approve(ALICE, 10);
        token.approve(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_noMintBurnOrAdministrationEvenForDeployer() public {
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 1);
        calls[1] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[2] = abi.encodeWithSignature("pause()");
        calls[3] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[4] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[5] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[6] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[7] = abi.encodeWithSignature("setFee(uint256)", 100);
        for (uint256 i; i < calls.length; ++i) {
            (bool asDeployer,) = address(token).call(calls[i]);
            assertFalse(asDeployer);
            vm.prank(ALICE);
            (bool asOther,) = address(token).call(calls[i]);
            assertFalse(asOther);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_transfersConserveSupply(uint256 rawFirst, uint256 rawSecond) public {
        uint256 first = bound(rawFirst, 0, SUPPLY);
        uint256 second = bound(rawSecond, 0, first);
        token.transfer(ALICE, first);
        vm.prank(ALICE);
        token.transfer(BOB, second);
        assertEq(token.balanceOf(address(this)), SUPPLY - first);
        assertEq(token.balanceOf(ALICE), first - second);
        assertEq(token.balanceOf(BOB), second);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 rawApproved, uint256 rawSpent) public {
        uint256 approved = bound(rawApproved, 0, SUPPLY);
        uint256 spent = bound(rawSpent, 0, approved);
        token.approve(ALICE, approved);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, spent);
        assertEq(token.allowance(address(this), ALICE), approved - spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(BOB), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
