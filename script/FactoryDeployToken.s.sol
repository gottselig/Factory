// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/OlegToken.sol";
import "../src/TokenFactory.sol";

/**
 * @title FactoryDeployTokenScript
 *
 * Использует уже развёрнутую TokenFactory для создания нового клона OlegToken.
 *
 * Переменные окружения:
 *   FACTORY_ADDRESS      — адрес TokenFactory (или читается из deploy-out.json)
 *   DEPLOYER_PRIVATE_KEY — приватный ключ деплоера
 *   TOKEN_NAME           — название нового токена (по умолчанию "CloneToken")
 *   TOKEN_SYMBOL         — символ нового токена (по умолчанию "CLN")
 *   TOKEN_ADMIN          — адрес admin нового токена (по умолчанию deployer)
 *   ETHERSCAN_API_KEY    — ключ для верификации
 *
 * Верификация клонов:
 *   Клоны EIP-1167 верифицируются автоматически через ссылку на implementation.
 *   Используйте: forge verify-contract <CLONE> src/OlegToken.sol:OlegToken --chain <CHAIN_ID>
 */
contract FactoryDeployTokenScript is Script {
    function run() external {
        uint256 deployerKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);

        address factoryAddr = vm.envOr(
            "FACTORY_ADDRESS",
            _readFromFile("factory")
        );
        require(factoryAddr != address(0), "FactoryDeployTokenScript: FACTORY_ADDRESS not set");

        string memory name_   = vm.envOr("TOKEN_NAME",   string("CloneToken"));
        string memory symbol_ = vm.envOr("TOKEN_SYMBOL", string("CLN"));
        address admin         = vm.envOr("TOKEN_ADMIN",  deployer);

        console.log("=== Deploy clone via TokenFactory ===");
        console.log("Factory:", factoryAddr);
        console.log("Name   :", name_);
        console.log("Symbol :", symbol_);
        console.log("Admin  :", admin);

        vm.startBroadcast(deployerKey);

        TokenFactory factory = TokenFactory(factoryAddr);
        address clone = factory.deployToken(name_, symbol_, address(0), admin);

        console.log("Clone deployed:", clone);
        console.log("Total clones  :", factory.tokensCount());

        vm.stopBroadcast();
    }

    function _readFromFile(string memory key) internal view returns (address) {
        try vm.readFile("deploy-out.json") returns (string memory json) {
            return vm.parseJsonAddress(json, string.concat(".", key));
        } catch {
            return address(0);
        }
    }
}
