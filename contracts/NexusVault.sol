// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/INexusERC20.sol";
import "./interfaces/INexusERC721.sol";

/// @custom:security-contact security@nexusdao.money
contract NexusVault is ERC721Holder, Ownable {
    mapping(uint256 => uint256) public tokenIdToTimestamp;
    mapping(uint256 => address) public tokenIdToStaker;
    mapping(address => uint256[]) public stakerToTokenIds;

    bool public isWalletLimited = true;
    uint256 public maxPerWallet = 100;

    INexusERC20 public NXS;
    INexusERC721 public NEXUS;

    //
    // Modifiers
    //

    modifier whenNotBlacklisted() {
        require(
            !NXS.isInBlacklist(_msgSender()),
            "NexusVault: blacklisted address"
        );
        _;
    }

    //
    // Events
    //

    event TokenStaked(uint256 tokenId);
    event TokenUnstaked(uint256 tokenId);
    event RewardsClaimed(uint256 amount, address by);

    event NXSAddressUpdated(address from, address to);
    event NEXUSAddressUpdated(address from, address to);

    //
    // Constructor
    //

    constructor(address _NXS, address _NEXUS) {
        NXS = INexusERC20(_NXS);
        NEXUS = INexusERC721(_NEXUS);
    }

    //
    // Getters
    //

    function getTokensStaked(address staker)
        external
        view
        returns (uint256[] memory)
    {
        return stakerToTokenIds[staker];
    }

    function getRewardsByTokenId(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        return
            NEXUS.ownerOf(tokenId) != address(this)
                ? 0
                : (block.timestamp - tokenIdToTimestamp[tokenId]) *
                    NEXUS.getTokenEmissionRate(tokenId);
    }

    function getAllRewards(address staker) public view returns (uint256) {
        uint256[] memory tokenIds = stakerToTokenIds[staker];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalRewards += getRewardsByTokenId(tokenIds[i]);
        }

        return totalRewards;
    }

    function getStakerOf(uint256 tokenId) external view returns (address) {
        return tokenIdToStaker[tokenId];
    }

    //
    // Setters
    //

    function setIsWalletLimited(bool value) external onlyOwner {
        isWalletLimited = value;
    }

    function setMaxPerWallet(uint256 limit) external onlyOwner {
        maxPerWallet = limit;
    }

    function setNXSAddress(address _NXS) external onlyOwner {
        emit NXSAddressUpdated(address(NXS), _NXS);
        NXS = INexusERC20(_NXS);
    }

    function setNEXUSAddress(address _NEXUS) external onlyOwner {
        emit NEXUSAddressUpdated(address(NEXUS), _NEXUS);
        NEXUS = INexusERC721(_NEXUS);
    }

    //
    // Stake/Unstake/Claim
    //

    function stake(uint256[] calldata tokenIds) external whenNotBlacklisted {
        if (isWalletLimited) {
            require(
                stakerToTokenIds[_msgSender()].length + tokenIds.length <=
                    maxPerWallet,
                "NexusVault: wallet limit reached"
            );
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                NEXUS.ownerOf(tokenIds[i]) == _msgSender(),
                "NexusVault: owner and caller differ"
            );

            require(
                tokenIdToStaker[tokenIds[i]] == address(0),
                "NexusVault: token already staked"
            );

            emit TokenStaked(tokenIds[i]);

            NEXUS.safeTransferFrom(_msgSender(), address(this), tokenIds[i]);
            stakerToTokenIds[_msgSender()].push(tokenIds[i]);
            tokenIdToTimestamp[tokenIds[i]] = block.timestamp;
            tokenIdToStaker[tokenIds[i]] = _msgSender();
        }
    }

    function unstake(uint256[] calldata tokenIds) external whenNotBlacklisted {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == _msgSender(),
                "NexusVault: owner and caller differ"
            );

            emit TokenUnstaked(tokenIds[i]);

            totalRewards += getRewardsByTokenId(tokenIds[i]);
            _removeTokenIdFromStaker(_msgSender(), tokenIds[i]);
            tokenIdToStaker[tokenIds[i]] = address(0);

            NEXUS.safeTransferFrom(address(this), _msgSender(), tokenIds[i]);
        }

        emit RewardsClaimed(totalRewards, _msgSender());
        NXS.transfer(_msgSender(), totalRewards);
    }

    function claim(uint256[] calldata tokenIds) external whenNotBlacklisted {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == _msgSender(),
                "NexusVault: owner and caller differ"
            );

            totalRewards += getRewardsByTokenId(tokenIds[i]);
            tokenIdToTimestamp[tokenIds[i]] = block.timestamp;
        }

        emit RewardsClaimed(totalRewards, _msgSender());
        NXS.transfer(_msgSender(), totalRewards);
    }

    //
    // Cleanup
    //

    function _remove(address staker, uint256 index) internal {
        if (index >= stakerToTokenIds[staker].length) return;

        for (uint256 i = index; i < stakerToTokenIds[staker].length - 1; i++) {
            stakerToTokenIds[staker][i] = stakerToTokenIds[staker][i + 1];
        }

        stakerToTokenIds[staker].pop();
    }

    function _removeTokenIdFromStaker(address staker, uint256 tokenId)
        internal
    {
        for (uint256 i = 0; i < stakerToTokenIds[staker].length; i++) {
            if (stakerToTokenIds[staker][i] == tokenId) {
                _remove(staker, i);
            }
        }
    }
}
