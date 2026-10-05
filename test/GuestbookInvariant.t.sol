// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Guestbook} from "src/Guestbook.sol";

contract GuestbookHandler is Test {
    Guestbook public immutable book;
    address public constant OWNER = address(0xB000);
    bool public expectedPaused;
    mapping(address => bool) public expectedSigned;
    Guestbook.Entry[] private originals;

    constructor() {
        book = new Guestbook(OWNER);
    }

    function actor(uint256 seed) public pure returns (address) {
        // Include the owner as a normal signer as well as fifteen unrelated callers.
        return address(uint160(0xB000 + seed % 16));
    }

    function sign(uint8 actorSeed, bytes32 payload, uint16 rawLength, uint32 elapsed) public {
        address signer = actor(actorSeed);
        uint256 length = bound(rawLength, 0, 160);
        bytes memory message = new bytes(length);
        for (uint256 i; i < length; ++i) {
            message[i] = payload[i % 32];
        }
        uint256 signedAt = vm.getBlockTimestamp() + bound(elapsed, 0, 7 days);
        vm.warp(signedAt);

        if (expectedPaused) {
            vm.expectRevert(Guestbook.SigningPaused.selector);
        } else if (expectedSigned[signer]) {
            vm.expectRevert(abi.encodeWithSelector(Guestbook.AlreadySigned.selector, signer));
        } else if (length > 140) {
            vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, length));
        } else {
            vm.prank(signer);
            assertEq(book.sign(string(message)), originals.length, "incorrect append index");
            // Preserve the inputs, never populate the oracle by reading back the implementation.
            originals.push(Guestbook.Entry(signer, signedAt, string(message)));
            expectedSigned[signer] = true;
            return;
        }
        vm.prank(signer);
        book.sign(string(message));
    }

    function setPaused(bool paused) public {
        vm.prank(OWNER);
        book.setPaused(paused);
        expectedPaused = paused;
    }

    function unauthorizedPause(uint8 actorSeed, bool paused) external {
        address caller = actor(bound(actorSeed, 1, 15));
        vm.expectRevert(Guestbook.Unauthorized.selector);
        // Even an owner's transaction routed through another address has no pause authority.
        vm.prank(caller, OWNER);
        book.setPaused(paused);
    }

    function attemptRewrite(uint8 indexSeed, uint8 actionSeed) external {
        uint256 index = bound(indexSeed, 0, originals.length - 1);
        bytes memory data;
        if (actionSeed % 4 == 0) data = abi.encodeWithSignature("editEntry(uint256,string)", index, "rewrite");
        else if (actionSeed % 4 == 1) data = abi.encodeWithSignature("deleteEntry(uint256)", index);
        else if (actionSeed % 4 == 2) data = abi.encodeWithSignature("resetSigner(address)", originals[index].signer);
        else data = abi.encodeWithSignature("clear()");
        vm.prank(OWNER);
        (bool ok,) = address(book).call(data);
        assertFalse(ok, "owner gained entry mutation authority");
    }

    function expectedCount() external view returns (uint256) {
        return originals.length;
    }

    function original(uint256 index) external view returns (Guestbook.Entry memory) {
        return originals[index];
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract GuestbookInvariantTest is Test {
    GuestbookHandler private handler;
    Guestbook private book;

    function setUp() public {
        handler = new GuestbookHandler();
        book = handler.book();
        // Start with a permanent entry, so immutability is checked even before random signing.
        handler.sign(1, bytes32(uint256(123)), 140, 0);
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.sign.selector;
        selectors[1] = handler.setPaused.selector;
        selectors[2] = handler.unauthorizedPause.selector;
        selectors[3] = handler.attemptRewrite.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_entriesArePermanentAndBothLookupsAgree() public view {
        uint256 count = handler.expectedCount();
        assertEq(book.entryCount(), count, "entry created or removed unexpectedly");
        for (uint256 i; i < count; ++i) {
            Guestbook.Entry memory original = handler.original(i);
            assertEq(abi.encode(book.entryAt(i)), abi.encode(original), "entry changed by index");
            assertEq(abi.encode(book.entryBySigner(original.signer)), abi.encode(original), "entry changed by signer");
        }
        for (uint256 i; i < 16; ++i) {
            address signer = handler.actor(i);
            assertEq(book.hasSigned(signer), handler.expectedSigned(signer), "signature consumed or reset unexpectedly");
        }
    }

    function invariant_onlyOwnerControlsPause() public view {
        assertEq(book.owner(), handler.OWNER());
        assertEq(book.paused(), handler.expectedPaused(), "pause authority bypassed");
    }

    function test_handlerExercisesRejectionRetryAndPermanentEntries() public {
        handler.sign(2, bytes32(uint256(1)), 141, 1);
        assertFalse(book.hasSigned(handler.actor(2)));
        handler.setPaused(true);
        handler.sign(2, bytes32(uint256(2)), 1, 1);
        handler.unauthorizedPause(3, false);
        handler.setPaused(false);
        handler.sign(2, bytes32(uint256(3)), 1, 1);
        handler.sign(2, bytes32(uint256(4)), 1, 1);
        handler.attemptRewrite(1, 0);
        assertEq(book.entryCount(), 2);
        invariant_entriesArePermanentAndBothLookupsAgree();
        invariant_onlyOwnerControlsPause();
    }
}
