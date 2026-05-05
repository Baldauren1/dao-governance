// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Governance token with voting and permit support
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {

    // Total supply is 100 million tokens
    uint256 public constant MAX_SUPPLY = 100_000_000e18;

    // Percentages for distribution (using basis points)
    uint256 public constant TEAM_BPS = 4_000; // 40%
    uint256 public constant TREASURY_BPS  = 3_000; // 30%
    uint256 public constant COMMUNITY_BPS = 2_000; // 20%
    uint256 public constant LIQUIDITY_BPS = 1_000; // 10%

    // Target wallets
    address public immutable vestingContract;
    address public immutable treasury;
    address public immutable communityAirdrop;
    address public immutable liquidityPool;

    event TokensDistributed(
        address indexed vestingContract,
        address indexed treasury,
        address indexed communityAirdrop,
        address liquidityPool
    );

    constructor(
        address _vestingContract,
        address _treasury,
        address _communityAirdrop,
        address _liquidityPool
    )
        ERC20("DAO Governance Token", "GOV")
        ERC20Permit("DAO Governance Token")
        Ownable(msg.sender)
    {
        // Check for zero addresses
        require(_vestingContract != address(0), "GOV: zero addr vesting");
        require(_treasury != address(0), "GOV: zero addr treasury");
        require(_communityAirdrop != address(0), "GOV: zero addr airdrop");
        require(_liquidityPool != address(0), "GOV: zero addr liquidity");

        vestingContract = _vestingContract;
        treasury = _treasury;
        communityAirdrop = _communityAirdrop;
        liquidityPool = _liquidityPool;

        // Mint tokens based on the percentages defined above
        _mint(_vestingContract, (MAX_SUPPLY * TEAM_BPS) / 10_000); 
        _mint(_treasury, (MAX_SUPPLY * TREASURY_BPS) / 10_000); 
        _mint(_communityAirdrop, (MAX_SUPPLY * COMMUNITY_BPS) / 10_000); 
        _mint(_liquidityPool, (MAX_SUPPLY * LIQUIDITY_BPS) / 10_000); 

        emit TokensDistributed(
            _vestingContract, _treasury, _communityAirdrop, _liquidityPool
        );
    }

    // Overriding _update to work with ERC20Votes
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    // Needed for ERC20Permit and Nonces
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}