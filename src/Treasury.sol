// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// This contract holds the DAO's funds (ETH and tokens)
// Only the Timelock can move funds after a successful vote
contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    event ETHReceived(address indexed sender, uint256 amount);
    event ETHTransferred(address indexed to, uint256 amount);
    event ERC20Transferred(address indexed token, address indexed to, uint256 amount);

    // Timelock address should be the owner
    constructor(address timelockAddress) Ownable(timelockAddress) {}

    // Allow the contract to receive ETH
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    // Function to send ETH, only callable by the Timelock (owner)
    function transferETH(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Treasury: not enough ETH");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Treasury: transfer failed");
        emit ETHTransferred(to, amount);
    }

    // Function to send ERC20 tokens, also restricted to the Timelock
    function transferERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Transferred(token, to, amount);
    }

    // Helper functions to check balances
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
