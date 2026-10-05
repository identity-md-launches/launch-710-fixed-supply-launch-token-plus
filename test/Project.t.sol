// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {Guestbook} from "../src/Guestbook.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract DeploymentFactoryFixture {
    function deploy(address initialOwner) external returns (LaunchToken token, Guestbook book) {
        token = new LaunchToken();
        book = new Guestbook(initialOwner);
    }
}

contract ProjectTest is Test {
    address private constant OWNER = address(0xA11CE);

    function test_factoryGetsSupplyButExplicitOwnerGetsPauseAuthority() public {
        DeploymentFactoryFixture factory = new DeploymentFactoryFixture();
        (LaunchToken token, Guestbook book) = factory.deploy(OWNER);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(address(factory)), 10 ** 27);
        assertEq(token.balanceOf(address(book)), 0);
        assertEq(book.owner(), OWNER);
        vm.expectRevert(Guestbook.Unauthorized.selector);
        vm.prank(address(factory));
        book.setPaused(true);
        vm.prank(OWNER);
        book.setPaused(true);
        assertTrue(book.paused());
        assertEq(token.balanceOf(address(factory)), 10 ** 27);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function test_guestbookPauseHasNoEffectOnTokenTransfers() public {
        LaunchToken token = new LaunchToken();
        Guestbook book = new Guestbook(OWNER);
        vm.prank(OWNER);
        book.setPaused(true);
        assertTrue(token.transfer(OWNER, 10));
        assertEq(token.balanceOf(OWNER), 10);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function test_runtimeSizesAndForbiddenOpcodes() public {
        LaunchToken token = new LaunchToken();
        Guestbook book = new Guestbook(OWNER);
        _checkRuntime(address(token));
        _checkRuntime(address(book));
    }

    function test_scriptChainValidationWithExplicitInputs() public {
        Deploy script = new Deploy();
        vm.chainId(31337);
        script.checkChain(0);
        script.checkChain(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnexpectedChain.selector, 11155111, 31337));
        script.checkChain(11155111);

        vm.chainId(11155111);
        script.checkChain(11155111);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnexpectedChain.selector, 0, 11155111));
        script.checkChain(0);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnexpectedChain.selector, 31337, 11155111));
        script.checkChain(31337);

        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 1));
        script.checkChain(1);
    }

    function _checkRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }
}
