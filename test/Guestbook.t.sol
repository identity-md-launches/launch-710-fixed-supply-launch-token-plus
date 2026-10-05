// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Guestbook} from "../src/Guestbook.sol";

contract GuestbookTest is Test {
    Guestbook private book;
    address private constant OWNER = address(0xA11CE);
    address private constant ALICE = address(0xB0B);
    address private constant BOB = address(0xCAFE);

    function setUp() public {
        book = new Guestbook(OWNER);
    }

    function test_initialState() public view {
        assertEq(book.owner(), OWNER);
        assertFalse(book.paused());
        assertEq(book.entryCount(), 0);
        assertEq(book.MAX_MESSAGE_BYTES(), 140);
        assertFalse(book.hasSigned(ALICE));
    }

    function test_zeroOwnerRejected() public {
        vm.expectRevert(Guestbook.InvalidOwner.selector);
        new Guestbook(address(0));
    }

    function test_signEmitsAndBothLookupsReturnTheEntry() public {
        vm.warp(123456);
        vm.expectEmit(true, true, false, true, address(book));
        emit Guestbook.Signed(0, ALICE, "Hello, guestbook!", 123456);
        vm.prank(ALICE);
        assertEq(book.sign("Hello, guestbook!"), 0);

        assertEq(book.entryCount(), 1);
        assertTrue(book.hasSigned(ALICE));
        _assertEntry(0, ALICE, "Hello, guestbook!", 123456);
    }

    function test_distinctSignersCanUseTheSameMessage() public {
        vm.warp(100);
        vm.prank(ALICE);
        book.sign("Hello");
        vm.warp(200);
        vm.prank(BOB);
        assertEq(book.sign("Hello"), 1);
        _assertEntry(0, ALICE, "Hello", 100);
        _assertEntry(1, BOB, "Hello", 200);
        assertEq(book.entryCount(), 2);
    }

    function test_emptyMessageStillConsumesOnlySignature() public {
        uint256 timestamp = block.timestamp;
        vm.prank(ALICE);
        book.sign("");
        _assertEntry(0, ALICE, "", timestamp);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.AlreadySigned.selector, ALICE));
        vm.prank(ALICE);
        book.sign("replacement");
        assertEq(book.entryCount(), 1);
        _assertEntry(0, ALICE, "", timestamp);
    }

    function test_exactly140BytesAllowed() public {
        string memory message = string(new bytes(140));
        uint256 timestamp = block.timestamp;
        vm.prank(ALICE);
        book.sign(message);
        _assertEntry(0, ALICE, message, timestamp);
    }

    function test_141BytesRevertWithoutConsumingSignature() public {
        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, 141));
        vm.prank(ALICE);
        book.sign(string(new bytes(141)));
        assertEq(book.entryCount(), 0);
        assertFalse(book.hasSigned(ALICE));

        vm.prank(ALICE);
        book.sign("retry");
        assertEq(book.entryCount(), 1);
        assertEq(book.entryBySigner(ALICE).message, "retry");
    }

    function test_limitCountsUtf8BytesNotCharacters() public {
        bytes memory message;
        for (uint256 i; i < 70; ++i) {
            message = bytes.concat(message, bytes(unicode"é"));
        }
        assertEq(message.length, 140);
        vm.prank(ALICE);
        book.sign(string(message));

        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, 142));
        vm.prank(BOB);
        book.sign(string(bytes.concat(message, bytes(unicode"é"))));
        assertFalse(book.hasSigned(BOB));
        assertEq(book.entryCount(), 1);
    }

    function test_contractAddressCanSign() public {
        book.sign("contract caller");
        assertTrue(book.hasSigned(address(this)));
        assertEq(book.entryAt(0).signer, address(this));
    }

    function test_ownerHasNoSigningExemption() public {
        vm.startPrank(OWNER);
        book.sign("owner entry");
        vm.expectRevert(abi.encodeWithSelector(Guestbook.AlreadySigned.selector, OWNER));
        book.sign("owner rewrite");
        book.setPaused(true);
        vm.expectRevert(Guestbook.SigningPaused.selector);
        book.sign("still paused");
        vm.stopPrank();
        assertEq(book.entryCount(), 1);
        assertEq(book.entryBySigner(OWNER).message, "owner entry");
    }

    function test_missingSignerAndInvalidIndexRevert() public {
        vm.expectRevert(abi.encodeWithSelector(Guestbook.SignerNotFound.selector, ALICE));
        book.entryBySigner(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.SignerNotFound.selector, address(0)));
        book.entryBySigner(address(0));
        vm.expectRevert(abi.encodeWithSelector(Guestbook.EntryNotFound.selector, 0));
        book.entryAt(0);

        vm.prank(ALICE);
        book.sign("first");
        vm.expectRevert(abi.encodeWithSelector(Guestbook.EntryNotFound.selector, 1));
        book.entryAt(1);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.EntryNotFound.selector, type(uint256).max));
        book.entryAt(type(uint256).max);
        assertFalse(book.hasSigned(BOB));
    }

    function test_pauseResumePreservesEntriesAndRejectedSignerCanRetry() public {
        uint256 timestamp = block.timestamp;
        vm.prank(ALICE);
        book.sign("permanent");
        vm.expectEmit(false, false, false, true, address(book));
        emit Guestbook.PauseChanged(true);
        vm.prank(OWNER);
        book.setPaused(true);
        assertTrue(book.paused());
        _assertEntry(0, ALICE, "permanent", timestamp);

        vm.expectRevert(Guestbook.SigningPaused.selector);
        vm.prank(BOB);
        book.sign("retry later");
        assertEq(book.entryCount(), 1);
        assertFalse(book.hasSigned(BOB));

        vm.expectEmit(false, false, false, true, address(book));
        emit Guestbook.PauseChanged(false);
        vm.prank(OWNER);
        book.setPaused(false);
        assertFalse(book.paused());
        vm.prank(BOB);
        book.sign("retry later");
        vm.expectRevert(abi.encodeWithSelector(Guestbook.AlreadySigned.selector, ALICE));
        vm.prank(ALICE);
        book.sign("rewrite after resume");
        _assertEntry(0, ALICE, "permanent", timestamp);
        _assertEntry(1, BOB, "retry later", timestamp);
        assertEq(book.entryCount(), 2);
    }

    function test_nonOwnerCannotPauseOrResume() public {
        vm.expectRevert(Guestbook.Unauthorized.selector);
        vm.prank(ALICE);
        book.setPaused(true);
        assertFalse(book.paused());
        vm.prank(OWNER);
        book.setPaused(true);
        vm.expectRevert(Guestbook.Unauthorized.selector);
        vm.prank(ALICE);
        book.setPaused(false);
        assertTrue(book.paused());
    }

    function test_repeatedPauseStateIsAllowed() public {
        vm.startPrank(OWNER);
        book.setPaused(false);
        book.setPaused(true);
        book.setPaused(true);
        vm.stopPrank();
        assertTrue(book.paused());
        assertEq(book.entryCount(), 0);
    }

    function test_ownerCannotEditDeleteResetOrUpgrade() public {
        uint256 timestamp = block.timestamp;
        vm.prank(ALICE);
        book.sign("permanent");
        bytes[] memory calls = new bytes[](6);
        calls[0] = abi.encodeWithSignature("editEntry(uint256,string)", 0, "rewritten");
        calls[1] = abi.encodeWithSignature("deleteEntry(uint256)", 0);
        calls[2] = abi.encodeWithSignature("clear()");
        calls[3] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[4] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[5] = abi.encodeWithSignature("resetSigner(address)", ALICE);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(OWNER);
            (bool ok,) = address(book).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(book.owner(), OWNER);
        assertEq(book.entryCount(), 1);
        assertTrue(book.hasSigned(ALICE));
        _assertEntry(0, ALICE, "permanent", timestamp);
    }

    function test_directEtherAndPayableSigningRejected() public {
        vm.deal(ALICE, 2 ether);
        vm.prank(ALICE);
        (bool direct,) = address(book).call{value: 1 ether}("");
        assertFalse(direct);
        vm.prank(ALICE);
        (bool signing,) = address(book).call{value: 1 ether}(abi.encodeCall(book.sign, ("paid")));
        assertFalse(signing);
        assertEq(address(book).balance, 0);
        assertEq(book.entryCount(), 0);
        assertFalse(book.hasSigned(ALICE));
    }

    function testFuzz_messageLengthAndExactRoundTrip(address signer, bytes memory message) public {
        vm.assume(signer != address(0));
        uint256 timestamp = block.timestamp;
        if (message.length > 140) {
            vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, message.length));
            vm.prank(signer);
            book.sign(string(message));
            assertFalse(book.hasSigned(signer));
            assertEq(book.entryCount(), 0);
        } else {
            vm.prank(signer);
            book.sign(string(message));
            _assertEntry(0, signer, string(message), timestamp);
            vm.expectRevert(abi.encodeWithSelector(Guestbook.AlreadySigned.selector, signer));
            vm.prank(signer);
            book.sign("another message");
            assertEq(book.entryCount(), 1);
            _assertEntry(0, signer, string(message), timestamp);
        }
    }

    function testFuzz_onlyOwnerCanChangePause(address caller, bool newPaused) public {
        vm.assume(caller != OWNER);
        vm.expectRevert(Guestbook.Unauthorized.selector);
        vm.prank(caller);
        book.setPaused(newPaused);
        assertFalse(book.paused());
    }

    function testFuzz_appendAndPauseSequencePreservesEveryEntry(bytes32 seed, uint8 rawCount) public {
        uint256 count = bound(uint256(rawCount), 1, 16);
        for (uint256 i; i < count; ++i) {
            address signer = address(uint160(0x10000 + i));
            string memory message = string(abi.encode(seed, i));
            vm.warp(1_700_000_000 + i);
            if ((uint256(seed) >> i) & 1 == 1) {
                vm.prank(OWNER);
                book.setPaused(true);
                vm.expectRevert(Guestbook.SigningPaused.selector);
                vm.prank(signer);
                book.sign(message);
                assertFalse(book.hasSigned(signer));
                assertEq(book.entryCount(), i);
                vm.prank(OWNER);
                book.setPaused(false);
            }
            vm.prank(signer);
            assertEq(book.sign(message), i);
        }
        vm.prank(OWNER);
        book.setPaused(true);
        assertEq(book.entryCount(), count);
        for (uint256 i; i < count; ++i) {
            address signer = address(uint160(0x10000 + i));
            assertTrue(book.hasSigned(signer));
            _assertEntry(i, signer, string(abi.encode(seed, i)), 1_700_000_000 + i);
        }
        vm.prank(OWNER);
        book.setPaused(false);
        for (uint256 i; i < count; ++i) {
            address signer = address(uint160(0x10000 + i));
            vm.expectRevert(abi.encodeWithSelector(Guestbook.AlreadySigned.selector, signer));
            vm.prank(signer);
            book.sign("overwrite attempt");
            _assertEntry(i, signer, string(abi.encode(seed, i)), 1_700_000_000 + i);
        }
        assertEq(book.entryCount(), count);
    }

    function _assertEntry(uint256 index, address signer, string memory message, uint256 timestamp) private view {
        Guestbook.Entry memory byIndex = book.entryAt(index);
        Guestbook.Entry memory bySigner = book.entryBySigner(signer);
        assertEq(byIndex.signer, signer);
        assertEq(byIndex.signedAt, timestamp);
        assertEq(byIndex.message, message);
        assertEq(abi.encode(byIndex), abi.encode(bySigner));
    }
}
