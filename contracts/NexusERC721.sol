// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "./interfaces/INexusERC20.sol";
import "./interfaces/INexusVault.sol";

/// @custom:security-contact security@nexusdao.money
contract NexusERC721 is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    Ownable,
    Pausable
{
    uint256 public constant MAX_SUPPLY = 100_000;
    string public baseURI = "https://nexusdao.money/api/token/";

    struct TierInfo {
        uint256 price;
        uint256 emissionRate;
        uint256 count;
    }

    struct TokenInfo {
        uint256 id;
        uint256 tier;
        string name;
        bool isStaked;
        uint256 rewards;
    }

    TierInfo[] public tiers;

    mapping(uint256 => uint256) public tokenTier;
    mapping(uint256 => string) public tokenName;
    mapping(address => bool) public isAuthorized;

    INexusERC20 public NXS;
    INexusVault public vault;

    uint256 public rewardsPoolFee = 60;
    uint256 public treasuryFee = 30;
    uint256 public developerFee = 10;

    address public developer;
    address public treasury;

    //
    // Modifiers
    //

    modifier onlyAuthorized() {
        require(
            isAuthorized[_msgSender()],
            "NexusERC721: unauthorized address"
        );
        _;
    }

    modifier onlyValidTier(uint256 tier) {
        require(tier < tiers.length, "NexusERC721: unknown tier");
        _;
    }

    modifier whenTokenExists(uint256 tokenId) {
        require(_exists(tokenId), "NexusERC721: token doesn't exist");
        _;
    }

    modifier whenNotBlacklisted() {
        require(
            !NXS.isInBlacklist(_msgSender()),
            "NexusERC721: blacklisted address"
        );
        _;
    }

    modifier whenCallerIsOwner(uint256 tokenId) {
        require(
            ownerOf(tokenId) == _msgSender(),
            "NexusERC721: owner and caller differ"
        );
        _;
    }

    modifier whenValidName(string calldata name) {
        require(
            bytes(name).length > 3 && bytes(name).length < 32,
            "NexusERC721: invalid name length"
        );
        _;
    }

    modifier whenSupplyNotMaxed() {
        require(totalSupply() < MAX_SUPPLY, "NexusERC721: max supply reached");
        _;
    }

    //
    // Events
    //

    event AuthorizationUpdated(address account, bool value);
    event TokenUpgraded(uint256 tokenId, uint256 from, uint256 to);

    event DevAddressUpdated(address from, address to);
    event TreasuryAddressUpdated(address from, address to);

    event VaultAddressUpdated(address from, address to);
    event NXSAddressUpdated(address from, address to);

    event FeesUpdated(
        uint256 rewardsPoolFee,
        uint256 treasuryFee,
        uint256 developerFee
    );

    //
    // Constructor
    //

    constructor(address _NXS, address _treasury)
        ERC721("Nexus Ecosystem", "NEXUS")
    {
        developer = _msgSender();
        treasury = _treasury;

        NXS = INexusERC20(_NXS);

        isAuthorized[developer] = true;
        isAuthorized[treasury] = true;

        tiers.push(
            TierInfo({
                price: 60 * 10**18,
                emissionRate: 6430041152263,
                count: 0
            })
        );

        tiers.push(
            TierInfo({
                price: 30 * 10**18,
                emissionRate: 3215020576131,
                count: 0
            })
        );

        tiers.push(
            TierInfo({
                price: 10 * 10**18,
                emissionRate: 1071673525377,
                count: 0
            })
        );
    }

    //
    // Getters
    //

    function getTokenEmissionRate(uint256 tokenId)
        external
        view
        whenTokenExists(tokenId)
        returns (uint256)
    {
        return tiers[tokenTier[tokenId]].emissionRate;
    }

    function getTierPrice(uint256 tier)
        external
        view
        onlyValidTier(tier)
        returns (uint256)
    {
        return tiers[tier].price;
    }

    function getDetailedBalance(address account)
        external
        view
        returns (TokenInfo[] memory)
    {
        uint256[] memory stakedTokens = address(vault) != address(0)
            ? vault.getTokensStaked(account)
            : new uint256[](0);

        uint256 stakedCount = stakedTokens.length;
        uint256 unstakedCount = balanceOf(account);
        uint256 totalCount = stakedCount + unstakedCount;

        TokenInfo[] memory tokens = new TokenInfo[](totalCount);

        for (uint256 i = 0; i < unstakedCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(account, i);
            tokens[i] = TokenInfo(
                tokenId,
                tokenTier[tokenId],
                tokenName[tokenId],
                false,
                0
            );
        }

        for (uint256 i = 0; i < stakedCount; i++) {
            uint256 tokenId = stakedTokens[i];
            tokens[unstakedCount + i] = TokenInfo(
                tokenId,
                tokenTier[tokenId],
                tokenName[tokenId],
                true,
                vault.getRewardsByTokenId(tokenId)
            );
        }

        return tokens;
    }

    //
    // Setters
    //

    function setBaseURI(string calldata uri) external onlyOwner {
        baseURI = uri;
    }

    function setTierPrice(uint256 tier, uint256 price)
        external
        onlyOwner
        onlyValidTier(tier)
    {
        tiers[tier].price = price;
    }

    function setTierEmissionRate(uint256 tier, uint256 emissionRate)
        external
        onlyOwner
        onlyValidTier(tier)
    {
        tiers[tier].emissionRate = emissionRate;
    }

    function addNewTier(uint256 price, uint256 emissionRate)
        external
        onlyOwner
    {
        tiers.push(TierInfo(price, emissionRate, 0));
    }

    function removeLastTier() external onlyOwner {
        tiers.pop();
    }

    function upgradeTier(uint256 tokenId, uint256 tier)
        external
        onlyValidTier(tier)
        whenTokenExists(tokenId)
        whenCallerIsOwner(tokenId)
    {
        uint256 currentTier = tokenTier[tokenId];

        require(tier < currentTier, "NexusERC721: cannot downgrade tier");

        uint256 upgradeCost = tiers[tier].price - tiers[currentTier].price;

        NXS.burn(_msgSender(), upgradeCost);

        tiers[tier].count += 1;
        tiers[currentTier].count -= 1;
        tokenTier[tokenId] = tier;

        emit TokenUpgraded(tokenId, currentTier, tier);
    }

    function setTokenName(uint256 tokenId, string calldata name)
        external
        whenTokenExists(tokenId)
        whenCallerIsOwner(tokenId)
        whenValidName(name)
    {
        tokenName[tokenId] = name;
    }

    function updateAuthorization(address account, bool value)
        external
        onlyOwner
    {
        isAuthorized[account] = value;
        emit AuthorizationUpdated(account, value);
    }

    function setNXSAddress(address _NXS) external onlyOwner {
        emit NXSAddressUpdated(address(NXS), _NXS);
        NXS = INexusERC20(_NXS);
    }

    function setVaultAddress(address _vault) external onlyOwner {
        emit VaultAddressUpdated(address(vault), _vault);
        vault = INexusVault(_vault);
    }

    function setFees(
        uint256 _rewardsPoolFee,
        uint256 _treasuryFee,
        uint256 _developerFee
    ) external onlyOwner {
        require(
            _rewardsPoolFee + _treasuryFee + _developerFee == 100,
            "NexusERC721: fees not in percentage"
        );

        rewardsPoolFee = _rewardsPoolFee;
        treasuryFee = _treasuryFee;
        developerFee = _developerFee;

        emit FeesUpdated(rewardsPoolFee, treasuryFee, developerFee);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        emit TreasuryAddressUpdated(treasury, _treasury);
        treasury = _treasury;
    }

    function setDevAddress(address _developer) external onlyOwner {
        emit DevAddressUpdated(developer, _developer);
        developer = _developer;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    //
    // Mint functions
    //

    function _mintInternal(
        address to,
        uint256 tier,
        string calldata name
    ) internal {
        uint256 tokenId = totalSupply();

        tiers[tier].count += 1;
        tokenTier[tokenId] = tier;
        tokenName[tokenId] = name;
        _safeMint(to, tokenId);
    }

    function mint(
        address to,
        uint256 tier,
        string calldata name
    )
        external
        onlyValidTier(tier)
        whenValidName(name)
        whenSupplyNotMaxed
        onlyAuthorized
    {
        _mintInternal(to, tier, name);
    }

    function mintWithTokens(uint256 tier, string calldata name)
        external
        whenNotBlacklisted
        whenNotPaused
        whenSupplyNotMaxed
        whenValidName(name)
        onlyValidTier(tier)
    {
        require(
            address(vault) != address(0),
            "NexusERC721: vault address not set"
        );

        uint256 totalPayable = tiers[tier].price;
        uint256 vaultTokens = (totalPayable * rewardsPoolFee) / 100;
        uint256 treasuryTokens = (totalPayable * treasuryFee) / 100;
        uint256 devTokens = (totalPayable * developerFee) / 100;

        NXS.transferFrom(_msgSender(), address(this), totalPayable);
        NXS.transfer(treasury, treasuryTokens);
        NXS.transfer(developer, devTokens);
        NXS.transfer(address(vault), vaultTokens);

        _mintInternal(_msgSender(), tier, name);
    }

    //
    // Overrides
    //

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
