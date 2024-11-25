// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract Bank is Ownable {
    error InsufficientBalance();

    event Withdrawal(address indexed to, uint256 amount);
    event Deposit(address indexed from, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) { }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    // only owner(Governor) can withdraw
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (address(this).balance < amount) revert InsufficientBalance();
        Address.sendValue(payable(to), amount);
        emit Withdrawal(to, amount);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
