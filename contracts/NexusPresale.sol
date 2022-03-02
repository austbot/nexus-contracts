// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/INexusERC20.sol";
import "./interfaces/INexusERC721.sol";

/// @custom:security-contact security@nexusdao.money
contract NexusPresale is Ownable, Pausable {
    uint256 public constant PRIVATE_SALE_PRICE = 1;
    uint256 public constant PUBLIC_SALE_PRICE = 2;

    uint256 public constant DECIMALS = 10**18;
    uint256 public constant MAX_SOLD = 100_000 * DECIMALS;
    uint256 public constant MAX_BUY_PER_ADDRESS = 500 * DECIMALS;

    bool public isAnnounced;
    uint256 public startTime;
    uint256 public endTime;

    bool public isPublicSale;
    bool public isClaimable;

    uint256 public canClaimOnceIn = 1 days;
    uint256 public claimablePerDay = 50 * DECIMALS;
    uint256 public totalSold;
    uint256 public totalOwed;

    mapping(address => uint256) public invested;
    mapping(address => uint256) public lastClaimedAt;
    mapping(address => bool) public isWhitelisted;

    address public constant MIM = 0x130966628846BFd36ff31a822705796e8cb8C18D;
    address public treasury;

    INexusERC20 public NXS;
    INexusERC721 public NEXUS;

    //
    // Modifiers
    //

    modifier whenNotBlacklisted() {
        require(
            !NXS.isInBlacklist(_msgSender()),
            "NexusPresale: blacklisted address"
        );
        _;
    }

    modifier onlyEOA() {
        require(_msgSender() == tx.origin, "NexusPresale: not an EOA");
        _;
    }

    //
    // Events
    //

    event WhitelistUpdated(address account, bool value);
    event TokensBought(address account, uint256 amount, uint256 withMIM);
    event TokensClaimed(address account, uint256 amount);
    event NFTMinted(address by, uint256 tier, uint256 balance);

    //
    // Constructor
    //

    constructor(
        address _NXS,
        address _NEXUS,
        address _treasury
    ) {
        NXS = INexusERC20(_NXS);
        NEXUS = INexusERC721(_NEXUS);
        treasury = _treasury;
    }

    //
    // Setters
    //

    function announceICO(uint256 _startTime, uint256 _endTime)
        external
        onlyOwner
    {
        isAnnounced = true;
        startTime = _startTime;
        endTime = _endTime;
    }

    function startPublicSale() external onlyOwner {
        isPublicSale = true;
    }

    function enableClaiming() external onlyOwner {
        require(
            isAnnounced && block.timestamp > endTime,
            "NexusPresale: presale not ended yet"
        );

        isClaimable = true;
    }

    function setCanClaimOnceIn(uint256 _hours) external onlyOwner {
        canClaimOnceIn = _hours * 3600;
    }

    function setClaimablePerDay(uint256 amount) external onlyOwner {
        claimablePerDay = amount * DECIMALS;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    //
    // Whitelist functions
    //

    function addToWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = true;
            emit WhitelistUpdated(accounts[i], true);
        }
    }

    function removeFromWhitelist(address[] calldata accounts)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = false;
            emit WhitelistUpdated(accounts[i], false);
        }
    }

    function updateWhitelist(address account, bool value) external onlyOwner {
        isWhitelisted[account] = value;
        emit WhitelistUpdated(account, value);
    }

    //
    // Buy/Claim/Mint functions
    //

    function buyTokens(uint256 amount)
        external
        whenNotBlacklisted
        whenNotPaused
        onlyEOA
    {
        require(isAnnounced, "NexusPresale: not announced yet");

        require(
            block.timestamp > startTime,
            "NexusPresale: sale not started yet"
        );

        require(block.timestamp < endTime, "NexusPresale: sale ended");

        if (!isPublicSale) {
            require(
                isWhitelisted[_msgSender()],
                "NexusPresale: not a whitelisted address"
            );
        }

        require(totalSold < MAX_SOLD, "NexusPresale: sold out");
        require(amount > 0, "NexusPresale: zero buy amount");

        require(
            invested[_msgSender()] + amount <= MAX_BUY_PER_ADDRESS,
            "NexusPresale: wallet limit reached"
        );

        uint256 price = isPublicSale ? PUBLIC_SALE_PRICE : PRIVATE_SALE_PRICE;
        uint256 remaining = MAX_SOLD - totalSold;

        if (amount > remaining) {
            amount = remaining;
        }

        uint256 amountInMIM = amount * price;

        IERC20(MIM).transferFrom(_msgSender(), treasury, amountInMIM);

        invested[_msgSender()] += amount;
        totalSold += amount;
        totalOwed += amount;

        emit TokensBought(_msgSender(), amount, amountInMIM);
    }

    function claimTokens() external onlyEOA whenNotBlacklisted whenNotPaused {
        require(isClaimable, "NexusPresale: claiming not active");

        require(
            invested[_msgSender()] > 0,
            "NexusPresale: insufficient claimable balance"
        );

        require(
            block.timestamp > lastClaimedAt[_msgSender()] + canClaimOnceIn,
            "NexusPresale: already claimed once during permitted time"
        );

        lastClaimedAt[_msgSender()] = block.timestamp;

        uint256 claimableAmount = invested[_msgSender()];

        if (claimableAmount > claimablePerDay) {
            claimableAmount = claimablePerDay;
        }

        totalOwed -= claimableAmount;
        invested[_msgSender()] -= claimableAmount;

        NXS.transfer(_msgSender(), claimableAmount);

        emit TokensClaimed(_msgSender(), claimableAmount);
    }

    function mintFromInvested(uint256 tier, string calldata name)
        external
        onlyEOA
        whenNotBlacklisted
        whenNotPaused
    {
        require(isClaimable, "NexusPresale: presale not ended yet");

        uint256 price = NEXUS.getTierPrice(tier);

        require(
            invested[_msgSender()] >= price,
            "NexusPresale: insufficient presale balance"
        );

        totalOwed -= price;
        invested[_msgSender()] -= price;

        NEXUS.mint(_msgSender(), tier, name);
        emit NFTMinted(_msgSender(), tier, invested[_msgSender()]);
    }

    function withdrawTokens() external onlyOwner {
        require(totalOwed == 0, "NexusPresale: claim pending");
        NXS.transfer(_msgSender(), NXS.balanceOf(address(this)));
    }
}
