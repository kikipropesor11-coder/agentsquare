// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentSquare} from "../src/AgentSquare.sol";

/// @notice Minimal Foundry cheatcode interface (avoids an external forge-std dependency).
interface Vm {
    function prank(address) external;
}

/// @notice Test-only stand-in for the Agent ID registry: balanceOf is set by hand.
contract MockAgentIdRegistry {
    mapping(address => uint256) public balanceOf;

    function setBalance(address account, uint256 amount) external {
        balanceOf[account] = amount;
    }
}

contract AgentSquareTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    AgentSquare internal square;
    MockAgentIdRegistry internal registry;

    address internal constant AGENT_A = address(0xA11CE);
    address internal constant AGENT_B = address(0xB0B);
    address internal constant HUMAN = address(0x1234);

    function setUp() public {
        registry = new MockAgentIdRegistry();
        registry.setBalance(AGENT_A, 1);
        registry.setBalance(AGENT_B, 1);
        square = new AgentSquare(address(registry));
    }

    function testNonAgentCannotPost() public {
        vm.prank(HUMAN);
        try square.post("intro", "hello") {
            revert("expected revert");
        } catch (bytes memory reason) {
            require(
                keccak256(reason) == keccak256(abi.encodeWithSelector(AgentSquare.NotAnAgent.selector)),
                "wrong error"
            );
        }
    }

    function testAgentCanPostAndReply() public {
        vm.prank(AGENT_A);
        uint256 id = square.post("intro", "I am agent A");
        require(id == 0, "first post id");
        require(square.postCount() == 1, "post count");
        vm.prank(AGENT_B);
        square.reply(id, "welcome A");
        require(square.replyCountOf(id) == 1, "reply count");
        require(square.uniqueAgents() == 2, "unique agents");
        require(square.totalInteractions() == 2, "total interactions");
    }

    function testEndorseRules() public {
        vm.prank(AGENT_A);
        square.endorse(AGENT_B);
        require(square.endorsementsReceived(AGENT_B) == 1, "endorsement counted");
        vm.prank(AGENT_A);
        try square.endorse(AGENT_A) {
            revert("expected revert");
        } catch {}
        vm.prank(AGENT_A);
        try square.endorse(AGENT_B) {
            revert("expected revert");
        } catch {}
        vm.prank(AGENT_A);
        try square.endorse(HUMAN) {
            revert("expected revert");
        } catch {}
    }

    function testEmptyMessageRejected() public {
        vm.prank(AGENT_A);
        try square.post("x", "") {
            revert("expected revert");
        } catch {}
    }

    function testGateReadsRegistry() public view {
        require(square.isAgent(AGENT_A), "A is agent");
        require(!square.isAgent(HUMAN), "human is not agent");
    }
}
