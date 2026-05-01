// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/OlegToken.sol";
import "../src/OlegTokenV2.sol";
import "../src/TokenFactory.sol";

/**
 * @title DeployScript
 *
 * Разворачивает:
 *   1. OlegToken (реализация UUPS)
 *   2. ERC1967Proxy → OlegToken (прокси-токен)
 *   3. TokenFactory (с адресом реализации)
 *
 * Переменные окружения (опционально):
 *   DEPLOYER_PRIVATE_KEY — приватный ключ деплоера (по умолчанию первый ключ anvil)
 *   TRUSTED_FORWARDER    — адрес ERC2771-форвардера (по умолчанию address(0))
 */
contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);
        address forwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        console.log("=== Deploy OlegToken + TokenFactory ===");
        console.log("Deployer :", deployer);
        console.log("Forwarder:", forwarder);

        vm.startBroadcast(deployerKey);

        // 1. Реализация OlegToken
        OlegToken impl = new OlegToken();
        console.log("OlegToken implementation:", address(impl));

        // 2. Прокси с инициализацией
        bytes memory initData = abi.encodeCall(
            OlegToken.initialize,
            ("OlegToken", "OTK", forwarder, deployer)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("OlegToken proxy (UUPS)  :", address(proxy));

        // 3. TokenFactory
        TokenFactory factory = new TokenFactory(address(impl));
        console.log("TokenFactory            :", address(factory));

        vm.stopBroadcast();

        // Сохраняем адреса в файл для последующих скриптов
        string memory json = string.concat(
            '{"implementation":"', vm.toString(address(impl)),
            '","proxy":"',         vm.toString(address(proxy)),
            '","factory":"',       vm.toString(address(factory)),
            '"}'
        );
        vm.writeFile("deploy-out.json", json);
        console.log("Addresses saved to deploy-out.json");
    }
}
