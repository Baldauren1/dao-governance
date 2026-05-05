// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
//part 2
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Simple contract to test governance
// The Timelock contract will be the owner, so only proposals can change the state
contract Box is Ownable {
    uint256 private _value;
    uint256 public feePercentage; // another parameter to change via voting

    event ValueChanged(uint256 indexed oldValue, uint256 indexed newValue);
    event FeeChanged(uint256 indexed oldFee, uint256 indexed newFee);

    // Pass the Timelock address here to make it the owner
    constructor(address timelockAddress) Ownable(timelockAddress) {
        feePercentage = 100; // default 1%
    }

    // This can only be called if a governance proposal passes
    function store(uint256 newValue) external onlyOwner {
        uint256 old = _value;
        _value = newValue;
        emit ValueChanged(old, newValue);
    }

    // Another function to demonstrate multi-call or different proposals
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= 10_000, "Box: fee too high");
        uint256 old = feePercentage;
        feePercentage = newFee;
        emit FeeChanged(old, newFee);
    }

    // Just a basic getter
    function retrieve() external view returns (uint256) {
        return _value;
    }
}
