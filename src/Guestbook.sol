// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice One permanent entry per calling address; the owner can pause new entries.
contract Guestbook {
    struct Entry {
        address signer;
        uint256 signedAt;
        string message;
    }

    error InvalidOwner();
    error Unauthorized();
    error SigningPaused();
    error AlreadySigned(address signer);
    error MessageTooLong(uint256 length);
    error EntryNotFound(uint256 index);
    error SignerNotFound(address signer);

    event Signed(uint256 indexed index, address indexed signer, string message, uint256 signedAt);
    event PauseChanged(bool paused);

    uint256 public constant MAX_MESSAGE_BYTES = 140;
    address public immutable owner;
    bool public paused;

    Entry[] private _entries;
    // Zero means absent; storing index + 1 distinguishes the first entry from absence.
    mapping(address signer => uint256 id) private _entryIds;

    /// @param initialOwner Explicit pause authority, including when deployed through a factory.
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert InvalidOwner();
        owner = initialOwner;
    }

    /// @notice Append the caller's only entry. Empty messages are allowed; length is in bytes.
    /// @return index The zero-based index of the new entry.
    function sign(string calldata message) external returns (uint256 index) {
        if (paused) revert SigningPaused();
        if (_entryIds[msg.sender] != 0) revert AlreadySigned(msg.sender);
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong(bytes(message).length);

        index = _entries.length;
        _entryIds[msg.sender] = index + 1;
        _entries.push(Entry(msg.sender, block.timestamp, message));
        emit Signed(index, msg.sender, message, block.timestamp);
    }

    /// @notice Pause or resume new signatures. Existing entries are always readable.
    /// @dev Repeating the current state is allowed and emits the same event.
    function setPaused(bool newPaused) external {
        if (msg.sender != owner) revert Unauthorized();
        paused = newPaused;
        emit PauseChanged(newPaused);
    }

    function entryCount() external view returns (uint256) {
        return _entries.length;
    }

    function hasSigned(address signer) external view returns (bool) {
        return _entryIds[signer] != 0;
    }

    function entryAt(uint256 index) external view returns (Entry memory) {
        if (index >= _entries.length) revert EntryNotFound(index);
        return _entries[index];
    }

    function entryBySigner(address signer) external view returns (Entry memory) {
        uint256 id = _entryIds[signer];
        if (id == 0) revert SignerNotFound(signer);
        return _entries[id - 1];
    }
}
