// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/OlegToken.sol";
import "../src/OlegTokenV2.sol";

/**
 * @title UpgradeScript
 *
 * Обновляет существующий UUPS-прокси с OlegToken до OlegTokenV2.
 * Устанавливает cap = 1_000_000 OTK.
 *
 * Переменные окружения:
 *   PROXY_ADDRESS        — адрес прокси (обязательно)
 *   DEPLOYER_PRIVATE_KEY — приватный ключ деплоера
 *   TOKEN_CAP            — максимальный supply (по умолчанию 1_000_000 * 1e18)
 *   ETHERSCAN_API_KEY    — ключ для верификации
 *
 * Верификация:
 *   forge script script/Upgrade.s.sol --network sepolia --broadcast --verify
 */
contract UpgradeScript is Script {
    function run() external {
        uint256 deployerKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address proxyAddr = vm.envOr(
            "PROXY_ADDRESS",
            _readProxyFromFile()
        );
        uint256 cap = vm.envOr("TOKEN_CAP", uint256(1_000_000e18));

        require(proxyAddr != address(0), "UpgradeScript: PROXY_ADDRESS not set");

        console.log("=== Upgrade OlegToken -> OlegTokenV2 ===");
        console.log("Proxy :", proxyAddr);
        console.log("Cap   :", cap);

        vm.startBroadcast(deployerKey);

        // Новая реализация
        OlegTokenV2 implV2 = new OlegTokenV2();
        console.log("OlegTokenV2 implementation:", address(implV2));

        // Вызываем upgradeToAndCall через интерфейс прокси
        OlegToken proxy = OlegToken(proxyAddr);
        proxy.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(OlegTokenV2.initializeV2, (cap))
        );
        console.log("Proxy upgraded. Version:", OlegTokenV2(proxyAddr).version());

        vm.stopBroadcast();

        string memory etherscanKey = vm.envOr("ETHERSCAN_API_KEY", string(""));
        if (bytes(etherscanKey).length == 0) {
            console.log("");
            console.log("--- Manual verification ---");
            console.log("forge verify-contract <IMPL_V2> src/OlegTokenV2.sol:OlegTokenV2 --chain <CHAIN_ID>");
        }
    }

    function _readProxyFromFile() internal returns (address) {
        try vm.readFile("deploy-out.json") returns (string memory json) {
            return vm.parseJsonAddress(json, ".proxy");
        } catch {
            return address(0);
        }
    }
}
