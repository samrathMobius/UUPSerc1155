const { ethers, upgrades } = require("hardhat");

async function main() {

  const owner = "0x717cbCF10015709A38c9429F8b2626129896B369";
  
  AuctionLibrary = await ethers.getContractFactory("AuctionLibrary");
  auctionLibrary = await AuctionLibrary.deploy();
  
  MarketplaceLibrary = await ethers.getContractFactory("MarketplaceLibrary");
  marketplaceLibrary = await MarketplaceLibrary.deploy();

  const OptimizedERC1155 = await ethers.getContractFactory("OptimizedERC1155",{
      libraries: {
          AuctionLibrary: auctionLibrary,
          MarketplaceLibrary: marketplaceLibrary,
      },
  });

  const optimizedERC1155 = await upgrades.deployProxy(OptimizedERC1155, [owner], {
    unsafeAllowLinkedLibraries: true,
    initializer: "initialize"
  });
  console.log("UpgradeErc1155 deployed to:", optimizedERC1155.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
