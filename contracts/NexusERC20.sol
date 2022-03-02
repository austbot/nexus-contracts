// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";

/// @custom:security-contact security@nexusdao.money
contract NexusERC20 is ERC20, Ownable {
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isAuthorized;
    mapping(address => bool) public isTaxFree;

    bool _inSwap;
    bool public taxEnabled = true;
    bool public useAntibot = true;

    uint256 public taxPercent = 10;
    uint256 public burnPercent = 2;
    uint256 public totalBurned;

    IJoeRouter02 public router;
    IERC721 public NEXUS;
    address public taxReceiver;
    address public pair;

    //
    // Modifiers
    //

    modifier whenNotBlacklisted(address account) {
        require(!isBlacklisted[account], "NexusERC20: blacklisted address");
        _;
    }

    modifier onlyAuthorized() {
        require(isAuthorized[_msgSender()], "NexusERC20: unauthorized address");
        _;
    }

    modifier swapping() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    //
    // Events
    //

    event RouterUpdated(address oldRouter, address newRouter);
    event PairUpdated(address oldPair, address newPair);
    event BlacklistUpdated(address account, bool value);
    event TaxExemptionUpdated(address account, bool value);
    event AuthorizationUpdated(address account, bool value);
    event TokensBurned(uint256 amount, address from, address by);

    //
    // Constructor
    //

    constructor() ERC20("Nexus", "NXS") {
        isTaxFree[_msgSender()] = true;
        isAuthorized[_msgSender()] = true;

        _mint(_msgSender(), 1_000_000 * 10**decimals());

        router = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        pair = IJoeFactory(router.factory()).createPair(
            address(this),
            router.WAVAX()
        );
    }

    //
    // Authorized-only functions
    //

    function burn(address from, uint256 amount) external onlyAuthorized {
        _burn(from, amount);
        emit TokensBurned(amount, from, _msgSender());
    }

    //
    // Getters
    //

    function isInBlacklist(address account) external view returns (bool) {
        return isBlacklisted[account];
    }

    //
    // Setters
    //

    function updateBlacklist(address account, bool value) external onlyOwner {
        isBlacklisted[account] = value;
        emit BlacklistUpdated(account, value);
    }

    function updateAuthorization(address account, bool value)
        external
        onlyOwner
    {
        isAuthorized[account] = value;
        emit AuthorizationUpdated(account, value);
    }

    function updateTaxExemption(address account, bool value)
        external
        onlyOwner
    {
        isTaxFree[account] = value;
        emit TaxExemptionUpdated(account, value);
    }

    function toggleTaxEnabled() external onlyOwner {
        taxEnabled = !taxEnabled;
    }

    function toggleUseAntibot() external onlyOwner {
        useAntibot = !useAntibot;
    }

    function setTaxPercent(uint256 percent) external onlyOwner {
        taxPercent = percent;
    }

    function setBurnPercent(uint256 percent) external onlyOwner {
        burnPercent = percent;
    }

    function setRouterAddress(address _router) external onlyOwner {
        address oldRouter = address(router);
        address oldPair = pair;

        router = IJoeRouter02(_router);
        pair = IJoeFactory(router.factory()).createPair(
            address(this),
            router.WAVAX()
        );

        emit RouterUpdated(oldRouter, _router);
        emit PairUpdated(oldPair, pair);
    }

    function setNEXUSAddress(address _NEXUS) external onlyOwner {
        NEXUS = IERC721(_NEXUS);
    }

    function setTaxReceiver(address account) external onlyOwner {
        taxReceiver = account;
    }

    function setPairAddress(address _pair) external onlyOwner {
        emit PairUpdated(pair, _pair);
        pair = _pair;
    }

    //
    // Tax functions
    //

    function _swapForAVAXAndSendTo(address account, uint256 amount)
        internal
        swapping
    {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WAVAX();

        _approve(address(this), address(router), amount);
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            account,
            block.timestamp
        );
    }

    function _taxedTransfer(
        address sender,
        address recipient,
        uint256 amount
    )
        internal
        whenNotBlacklisted(_msgSender())
        whenNotBlacklisted(sender)
        whenNotBlacklisted(recipient)
    {
        if (_inSwap) {
            _transfer(sender, recipient, amount);
            return;
        }

        require(taxReceiver != address(0), "NexusERC20: tax receiver not set");

        if ((recipient == pair) && !isTaxFree[sender] && taxEnabled) {
            if (useAntibot) {
                require(
                    address(NEXUS) != address(0),
                    "NexusERC20: ERC721 address not set"
                );

                require(
                    NEXUS.balanceOf(sender) > 0,
                    "NexusERC20: antibot mechanism in use"
                );
            }

            uint256 burnAmount = (amount * burnPercent) / 100;
            uint256 taxAmount = (amount * taxPercent) / 100;

            amount -= burnAmount + taxAmount;
            totalBurned += burnAmount;

            _transfer(sender, address(this), burnAmount + taxAmount);
            _swapForAVAXAndSendTo(taxReceiver, taxAmount);
            _burn(address(this), burnAmount);
        }

        _transfer(sender, recipient, amount);
    }

    //
    // Overrides
    //

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _taxedTransfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _taxedTransfer(sender, recipient, amount);

        uint256 currentAllowance = allowance(sender, _msgSender());

        require(
            currentAllowance >= amount,
            "NexusERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }
}
