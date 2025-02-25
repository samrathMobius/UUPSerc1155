const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const TokenModule = buildModule("TokenModule", (m) => {
  const token = m.contract("MobiusNFT", ["0x717cbCF10015709A38c9429F8b2626129896B369"]);

  return { token };
});

module.exports = TokenModule;