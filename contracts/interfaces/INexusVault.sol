// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface INexusVault {
    function getTokensStaked(address staker)
        external
        view
        returns (uint256[] memory);

    function getRewardsByTokenId(uint256 tokenId)
        external
        view
        returns (uint256);

    function getAllRewards(address staker) external view returns (uint256);

    function getStakerOf(uint256 tokenId) external view returns (address);
}
