const Svault = artifacts.require("Svault");

const migration = async (deployer, network, accounts) => {
    await Promise.all([
        deployToken(deployer, network),
    ]);
};

module.exports = migration;

async function deployToken(deployer, network) {
    await deployer.deploy(Svault,
            "0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8",
            "0xD7B7d3C0bdA57723Fb54ab95Fd8F9EA033AF37f2",
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
            "Svault",
            "0x2D2Ae0bfE25503f608f0f5cdCe54c17302C01Ea9");
};