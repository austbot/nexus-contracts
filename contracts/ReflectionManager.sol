// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/INexusERC721.sol";
import "./interfaces/INexusVault.sol";

/// @custom:security-contact security@nexusdao.money
contract ReflectionManager is Ownable {
    address public distributor;
    uint256 public nextDistributionIn;
    uint256 public distributeOnceIn;
    uint256 public totalDistributed;

    address[] public shareholders;
    uint256[] public shares;
    uint256 public totalShares;

    mapping(address => uint256) public reflections;
    mapping(address => bool) public isShareCalculated;

    bool public isDataPopulated;

    INexusERC721 public NEXUS;
    INexusVault public vault;

    //
    // Modifiers
    //

    modifier onlyDistributor() {
        require(
            _msgSender() == distributor,
            "ReflectionManager: unauthorized address"
        );
        _;
    }

    //
    // Events
    //

    event AVAXDistributed(uint256 amount, address to);
    event AVAXReceived(uint256 amount, address from);
    event Distributed(uint256 amount);

    //
    // Constructor
    //

    constructor(
        address _distributor,
        uint256 _nextDistributionIn,
        uint256 _distributeOnceIn,
        address _NEXUS,
        address _vault
    ) {
        distributor = _distributor;
        nextDistributionIn = _nextDistributionIn;
        distributeOnceIn = _distributeOnceIn * 3600;
        NEXUS = INexusERC721(_NEXUS);
        vault = INexusVault(_vault);
    }

    receive() external payable {
        emit AVAXReceived(msg.value, _msgSender());
    }

    function withdraw() external onlyOwner {
        Address.sendValue(payable(_msgSender()), address(this).balance);
    }

    //
    // Setters
    //

    function setDistributorAddress(address account) external onlyOwner {
        distributor = account;
    }

    function setNextDistributionIn(uint256 timestamp) external onlyOwner {
        nextDistributionIn = timestamp;
    }

    function setDistributeOnceIn(uint256 _hours) external onlyOwner {
        distributeOnceIn = _hours * 3600;
    }

    //
    // Distribution functions
    //

    function populateData() external onlyDistributor {
        shareholders = new address[](0);
        shares = new uint256[](0);
        totalShares = 0;

        uint256 stakedCount = NEXUS.balanceOf(address(vault));

        for (uint256 i = 0; i < stakedCount; i++) {
            uint256 tokenId = NEXUS.tokenOfOwnerByIndex(address(vault), i);
            address ownedBy = vault.getStakerOf(tokenId);

            if (!isShareCalculated[ownedBy]) {
                isShareCalculated[ownedBy] = true;

                uint256 ownerRewards = vault.getAllRewards(ownedBy);
                totalShares += ownerRewards;

                shareholders.push(ownedBy);
                shares.push(ownerRewards);
            }
        }

        isDataPopulated = true;
    }

    function resetData() external onlyDistributor {
        for (uint256 i = 0; i < shareholders.length; i++) {
            isShareCalculated[shareholders[i]] = false;
        }

        isDataPopulated = false;
        shareholders = new address[](0);
        shares = new uint256[](0);
        totalShares = 0;
    }

    function distribute() external onlyDistributor {
        require(isDataPopulated, "ReflectionManager: data not calculated");

        uint256 balance = address(this).balance;

        for (uint256 i = 0; i < shareholders.length; i++) {
            uint256 reflection = (shares[i] / totalShares) * balance;
            address payee = shareholders[i];

            emit AVAXDistributed(reflection, payee);

            Address.sendValue(payable(payee), reflection);
            reflections[payee] += reflection;
            isShareCalculated[payee] = false;
        }

        isDataPopulated = false;
        nextDistributionIn = block.timestamp + distributeOnceIn;
        totalDistributed += balance;

        emit Distributed(balance);
    }
}
