// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import {ERC1155BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1155HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./AuctionLibrary.sol";
import "./MarketplaceLibrary.sol";

contract OptimizedERC1155 is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    AccessControlUpgradeable,
    ERC1155HolderUpgradeable,
    ERC1155PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AuctionLibrary for AuctionLibrary.AuctionStorage;
    using MarketplaceLibrary for MarketplaceLibrary.MarketplaceStorage;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event Minted(
        address indexed user,
        uint256 tokenId,
        uint256 amount,
        string tokenURI
    );
    event UserBlacklisted(address indexed user);
    event UserRemovedFromBlacklist(address indexed user);

    event AuctionStarted(
        address indexed seller,
        uint256 auctionId,
        uint256 tokenId,
        uint256 amount,
        uint256 startingPrice,
        uint256 endTime
    );
    event BidPlaced(
        address indexed bidder,
        uint256 auctionId,
        uint256 amount,
        uint256 bidPerNFT
    );
    event AuctionEnded(
        uint256 auctionId,
        address indexed winner,
        uint256 highestBidPerNFT,
        uint256 totalAmountWon
    );

    mapping(uint256 => string) private _tokenURIs;
    mapping(address => bool) public blacklisted;

    uint256 private _tokenID;

    AuctionLibrary.AuctionStorage private auctionStorage;
    MarketplaceLibrary.MarketplaceStorage private _marketplace;

    /**
     * @dev Initializes the contract and grants roles to the initial owner.
     * @param initialOwner The address that will have admin and upgrader roles.
     */
    function initialize(address initialOwner) public initializer {
        __ERC1155_init("");
        __UUPSUpgradeable_init();
        __ERC1155Pausable_init();
        __AccessControl_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC1155Holder_init();
        __ReentrancyGuard_init();


        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(UPGRADER_ROLE, initialOwner);
    }
    
    /**
     * @dev Pauses all contract functionalities.
    */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpauses the contract.
    */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Mints a new token.
     * @param userAddress Recipient of the minted token.
     * @param amount Number of tokens to mint.
     * @param tokenURI URI of the token metadata.
     */
    function mint(
        address userAddress,
        uint256 amount,
        string memory tokenURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(amount > 0, "Amount should be greater than 0");
        require(!blacklisted[userAddress], "User is blacklisted");

        uint32 size;
        assembly {
            size := extcodesize(userAddress)
        }
        require(size == 0, "Cannot mint to a contract");

        _tokenID++;
        _mint(userAddress, _tokenID, amount, "");

        if (bytes(tokenURI).length > 0) {
            _setTokenURI(_tokenID, tokenURI);
            emit Minted(userAddress, _tokenID, 1, tokenURI);
        } else {
            emit Minted(userAddress, _tokenID, amount, "");
        }
    }
    
    /**
     * @dev Lists an NFT for sale.
     * @param tokenId ID of the token to list.
     * @param pricePerNFT Price per NFT.
     * @param amount Amount of tokens to list.
     */
    function listForSale(
        uint256 tokenId,
        uint256 pricePerNFT,
        uint256 amount
    ) external {
        require(bytes(_tokenURIs[tokenId]).length > 0, "Only NFTs can be listed for sale");
        require(
            balanceOf(msg.sender, tokenId) >= amount,
            "Insufficient tokens"
        );
        require(!blacklisted[msg.sender], "User is blacklisted");

        _safeTransferFrom(msg.sender, address(this), tokenId, amount, ""); // Move NFT to contract

        _marketplace.listForSale(tokenId, pricePerNFT, amount, msg.sender);
    }
    
    /**
     * @dev Purchases an NFT.
     * @param tokenId ID of the token to buy.
     * @param amount Amount of tokens to purchase.
     */
    function buyNFT(uint256 tokenId, uint256 amount) external payable {
        require(!blacklisted[msg.sender], "User is blacklisted");

        (address seller, uint256 price) = MarketplaceLibrary.buyNFT(
            _marketplace,
            tokenId,
            amount,
            msg.sender,
            msg.value
        );

        payable(seller).transfer(price);

        _safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
    }
    
    /**
     * @dev Removes a listing.
     * @param tokenId ID of the token to remove.
     */
    function removeListing(uint256 tokenId) external {
        _marketplace.removeListing(tokenId, msg.sender);
    }

    /**
     * @dev Starts an auction for an NFT.
     * @param tokenId ID of the token to auction.
     * @param amount Amount of NFT's to auction.
     * @param startingPricePerNFT Starting price per NFT.
     * @param duration Duration of the auction.
     */
    function startAuction(
        uint256 tokenId,
        uint256 amount,
        uint256 startingPricePerNFT,
        uint256 duration
    ) external whenNotPaused {
        require(bytes(_tokenURIs[tokenId]).length > 0, "Only NFTs can be auctioned");
        require(
            balanceOf(msg.sender, tokenId) >= amount,
            "Insufficient tokens"
        );
        require(startingPricePerNFT > 0, "Price must be greater than 0");
        require(duration > 0, "Invalid duration");
        require(!blacklisted[msg.sender], "User is blacklisted");

        uint256 auctionId = AuctionLibrary.startAuction(
            auctionStorage,
            tokenId,
            amount,
            startingPricePerNFT,
            duration,
            msg.sender
        );

        safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        emit AuctionStarted(
            msg.sender,
            auctionId,
            tokenId,
            amount,
            startingPricePerNFT,
            block.timestamp + duration
        );
    }
    
    /**
     * @dev Places a bid on an auction.
     * @param auctionId ID of the auction.
     * @param bidAmount Amount of NFT's to bid.
     * @param bidPerNFT Bid per NFT.
     */
    function placeBid(
        uint256 auctionId,
        uint256 bidAmount,
        uint256 bidPerNFT
    ) external payable whenNotPaused {
        require(!blacklisted[msg.sender], "User is blacklisted");

        uint256 bidValue = bidAmount * bidPerNFT;
        AuctionLibrary.placeBid(
            auctionStorage,
            auctionId,
            bidAmount,
            bidPerNFT,
            msg.sender,
            bidValue
        );

        emit BidPlaced(msg.sender, auctionId, bidAmount, bidPerNFT);
    }
    
    /**
     * @dev Ends an auction.
     * @param auctionId ID of the auction.
     */
    function endAuction(uint256 auctionId) external whenNotPaused {
        require(!blacklisted[msg.sender], "User is blacklisted");

        (
            bool hasWinner,
            address winner,
            uint256 highestBidPerNFT,
            uint256 totalAmountWon
        ) = AuctionLibrary.endAuction(auctionStorage, auctionId);

        if (hasWinner) {
            _safeTransferFrom(
                address(this),
                winner,
                auctionId,
                totalAmountWon,
                ""
            );
            emit AuctionEnded(
                auctionId,
                winner,
                highestBidPerNFT,
                totalAmountWon
            );
        }
    }
    
    /**
     * @dev Blacklists a user.
     * @param user Address of the user to blacklist.
     */
    function addToBlacklist(
        address user
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blacklisted[user] = true;
        emit UserBlacklisted(user);
    }
    
    /**
     * @dev Removes a user from the blacklist.
     * @param user Address of the user to remove from the blacklist.
     */
    function removeFromBlacklist(
        address user
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blacklisted[user] = false;
        emit UserRemovedFromBlacklist(user);
    }
    
    /**
     * @dev Returns the URI of a token.
     * @param tokenId ID of the token.
     * @param tokenURI of the token.
     */
    function _setTokenURI(uint256 tokenId, string memory tokenURI) internal {
        _tokenURIs[tokenId] = tokenURI;
    }
    
    
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    )
        internal
        override(
            ERC1155Upgradeable,
            ERC1155PausableUpgradeable,
            ERC1155SupplyUpgradeable
        )
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(
            ERC1155Upgradeable,
            ERC1155HolderUpgradeable,
            AccessControlUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }  

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }
}
