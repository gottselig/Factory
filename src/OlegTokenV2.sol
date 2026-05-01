// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OlegToken.sol";

/**
 * @title OlegTokenV2
 * @notice Обновлённая версия OlegToken, демонстрирующая UUPS-upgrade.
 *         Добавляет функцию cap (максимальный supply) и версию контракта.
 */
contract OlegTokenV2 is OlegToken {
    uint256 private _cap;

    event CapSet(uint256 cap);

    function initializeV2(uint256 cap_) external reinitializer(2) {
        _cap = cap_;
        emit CapSet(cap_);
    }

    function cap() public view returns (uint256) {
        return _cap;
    }

    function version() public pure returns (string memory) {
        return "2.0.0";
    }

    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) {
        require(_cap == 0 || totalSupply() + amount <= _cap, "OlegTokenV2: cap exceeded");
        _mint(to, amount);
    }
}
