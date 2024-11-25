// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { VoteToken } from "../src/VoteToken.sol";
import { Bank } from "../src/Bank.sol";
import { GovernorContract } from "../src/GovernorContract.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

contract BankGovernanceTest is Test {
    VoteToken public token;
    Bank public bank;
    GovernorContract public governor;

    address public owner;
    address public voter1;
    address public voter2;
    address public recipient;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1 million tokens
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50_400;

    function setUp() public {
        owner = address(this);
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        recipient = makeAddr("recipient");

        // depoly contracts
        token = new VoteToken(owner);
        governor = new GovernorContract(token, "MyDAO Governor");
        bank = new Bank(address(governor));

        // transfer tokens to test accounts
        token.transfer(voter1, 100_000 * 10 ** 18);
        token.transfer(voter2, 100_000 * 10 ** 18);

        // deposit some ETH to bank
        vm.deal(address(bank), 10 ether);
    }

    function test_InitialSetup() public view {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 200_000 * 10 ** 18);
        assertEq(token.balanceOf(voter1), 100_000 * 10 ** 18);
        assertEq(token.balanceOf(voter2), 100_000 * 10 ** 18);
        assertEq(address(bank).balance, 10 ether);
        assertEq(bank.owner(), address(governor));
    }

    function test_ProposalLifecycle() public {
        // delegate voting power to self
        vm.startPrank(voter1);
        token.delegate(voter1);
        vm.stopPrank();

        // delegate voting power to self
        vm.startPrank(voter2);
        token.delegate(voter2);
        vm.stopPrank();

        // create a proposal
        vm.startPrank(voter1);
        uint256 proposalId =
            governor.proposeBankWithdrawal(address(bank), recipient, 1 ether, "Send 1 ETH to recipient");
        vm.stopPrank();

        // wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // start voting
        vm.startPrank(voter1);
        governor.castVote(proposalId, 1); // support
        vm.stopPrank();

        vm.startPrank(voter2);
        governor.castVote(proposalId, 1); // support
        vm.stopPrank();

        // wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // check proposal state
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Succeeded));

        // execute proposal
        bytes memory callData = abi.encodeWithSignature("withdraw(address,uint256)", recipient, 1 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(bank);
        values[0] = 0;
        calldatas[0] = callData;

        vm.startPrank(voter1);
        governor.execute(targets, values, calldatas, keccak256(bytes("Send 1 ETH to recipient")));
        vm.stopPrank();

        // check result
        assertEq(address(bank).balance, 9 ether);
        assertEq(recipient.balance, 1 ether);
    }

    function test_FailedProposal() public {
        // delegate voting power to self
        vm.startPrank(voter1);
        token.delegate(voter1);
        vm.stopPrank();

        // create a proposal
        vm.startPrank(voter1);
        uint256 proposalId =
            governor.proposeBankWithdrawal(address(bank), recipient, 1 ether, "Send 1 ETH to recipient");
        vm.stopPrank();

        // wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // start voting
        vm.startPrank(voter1);
        governor.castVote(proposalId, 0); // against
        vm.stopPrank();

        // wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // check proposal state
        assertEq(uint256(governor.state(proposalId)), uint256(ProposalState.Defeated));
    }

    function test_DirectWithdrawFails() public {
        // try to withdraw directly from bank (should fail)
        vm.startPrank(voter1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, voter1));
        bank.withdraw(recipient, 1 ether);
        vm.stopPrank();

        assertEq(address(bank).balance, 10 ether);
    }
}
