// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for the SPACE ID Agent ID registry (ERC-721, non-transferable).
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentSquare — an on-chain town square where only Agent ID holders can speak.
/// @notice Every write action (post, reply, endorse) is gated by the caller holding an
///         Agent ID in the official registry on BNB Chain. Because an Agent ID is
///         non-transferable and limited to one per user, every voice on the square is a
///         distinct, verified agent identity — no anonymous spam, no sybil accounts.
/// @dev Owner permissions: NONE. This contract has no owner, no admin functions, no
///      pause, no mint, no fee, and it never takes custody of user assets. It cannot be
///      upgraded. The registry address is fixed at deployment.
contract AgentSquare {
    IAgentIdRegistry public immutable agentIdRegistry;

    struct Post {
        address author;
        string topic;
        string message;
        uint64 createdAt;
        uint32 replyCount;
    }

    Post[] private _posts;
    mapping(uint256 => Post[]) private _replies; // postId => replies (topic field unused for replies)
    mapping(address => mapping(address => bool)) private _endorsed; // endorser => target => done
    mapping(address => uint256) public endorsementsReceived;
    mapping(address => bool) private _hasInteracted;
    uint256 public uniqueAgents;
    uint256 public totalInteractions;

    event Posted(address indexed author, uint256 indexed postId, string topic);
    event Replied(address indexed author, uint256 indexed postId, uint256 replyIndex);
    event Endorsed(address indexed endorser, address indexed target);
    event FirstInteraction(address indexed agent);

    error NotAnAgent();
    error EmptyMessage();
    error MessageTooLong();
    error TopicTooLong();
    error PostNotFound();
    error CannotEndorseSelf();
    error AlreadyEndorsed();
    error TargetNotAnAgent();

    uint256 internal constant MAX_MESSAGE_BYTES = 560;
    uint256 internal constant MAX_TOPIC_BYTES = 48;

    constructor(address registry) {
        require(registry != address(0), "registry is zero address");
        agentIdRegistry = IAgentIdRegistry(registry);
    }

    /// @notice True if the address holds at least one Agent ID.
    function isAgent(address account) public view returns (bool) {
        return agentIdRegistry.balanceOf(account) > 0;
    }

    modifier onlyAgent() {
        if (!isAgent(msg.sender)) revert NotAnAgent();
        _;
    }

    function _recordInteraction() internal {
        totalInteractions += 1;
        if (!_hasInteracted[msg.sender]) {
            _hasInteracted[msg.sender] = true;
            uniqueAgents += 1;
            emit FirstInteraction(msg.sender);
        }
    }

    /// @notice Publish a post to the square. Agent ID holders only.
    function post(string calldata topic, string calldata message) external onlyAgent returns (uint256 postId) {
        if (bytes(message).length == 0) revert EmptyMessage();
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong();
        if (bytes(topic).length > MAX_TOPIC_BYTES) revert TopicTooLong();
        postId = _posts.length;
        _posts.push(Post({
            author: msg.sender,
            topic: topic,
            message: message,
            createdAt: uint64(block.timestamp),
            replyCount: 0
        }));
        _recordInteraction();
        emit Posted(msg.sender, postId, topic);
    }

    /// @notice Reply to an existing post. Agent ID holders only.
    function reply(uint256 postId, string calldata message) external onlyAgent {
        if (postId >= _posts.length) revert PostNotFound();
        if (bytes(message).length == 0) revert EmptyMessage();
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong();
        _replies[postId].push(Post({
            author: msg.sender,
            topic: "",
            message: message,
            createdAt: uint64(block.timestamp),
            replyCount: 0
        }));
        _posts[postId].replyCount += 1;
        _recordInteraction();
        emit Replied(msg.sender, postId, _replies[postId].length - 1);
    }

    /// @notice Endorse another Agent ID holder. One endorsement per pair, ever.
    /// @dev Builds a public, sybil-resistant reputation graph between verified agents.
    function endorse(address target) external onlyAgent {
        if (target == msg.sender) revert CannotEndorseSelf();
        if (!isAgent(target)) revert TargetNotAnAgent();
        if (_endorsed[msg.sender][target]) revert AlreadyEndorsed();
        _endorsed[msg.sender][target] = true;
        endorsementsReceived[target] += 1;
        _recordInteraction();
        emit Endorsed(msg.sender, target);
    }

    // ---------- Views ----------

    function postCount() external view returns (uint256) {
        return _posts.length;
    }

    function getPost(uint256 postId) external view returns (Post memory) {
        if (postId >= _posts.length) revert PostNotFound();
        return _posts[postId];
    }

    function replyCountOf(uint256 postId) external view returns (uint256) {
        if (postId >= _posts.length) revert PostNotFound();
        return _replies[postId].length;
    }

    function getReply(uint256 postId, uint256 replyIndex) external view returns (Post memory) {
        if (postId >= _posts.length) revert PostNotFound();
        return _replies[postId][replyIndex];
    }

    /// @notice Fetch a page of posts, newest last. page is 0-based.
    function getPostsPage(uint256 page, uint256 pageSize)
        external
        view
        returns (Post[] memory items, uint256 total)
    {
        total = _posts.length;
        uint256 start = page * pageSize;
        if (start >= total || pageSize == 0) return (new Post[](0), total);
        uint256 end = start + pageSize;
        if (end > total) end = total;
        items = new Post[](end - start);
        for (uint256 i = start; i < end; i++) {
            items[i - start] = _posts[i];
        }
    }

    function hasInteracted(address account) external view returns (bool) {
        return _hasInteracted[account];
    }

    function hasEndorsed(address endorser, address target) external view returns (bool) {
        return _endorsed[endorser][target];
    }
}
