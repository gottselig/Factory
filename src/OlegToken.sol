// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title OlegToken
 * @notice ERC20 токен с уровнями доступа (RBAC), мета-транзакциями (ERC2771 через storage),
 *         permit (ERC2612) и поддержкой UUPS-обновлений.
 *
 * Уровни доступа:
 *   - DEFAULT_ADMIN_ROLE — управление ролями, форвардером, обновлениями
 *   - MINTER_ROLE        — минт токенов
 *   - BURNER_ROLE        — сжигание токенов
 *   - UPGRADER_ROLE      — авторизация upgrade
 *
 * Мета-транзакции (ERC2771):
 *   Если вызов поступает от доверенного форвардера (_trustedForwarder),
 *   реальный отправитель извлекается из последних 20 байт calldata.
 *
 * Permit (ERC2612):
 *   Наследуется через ERC20PermitUpgradeable.
 */
contract OlegToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE   = keccak256("BURNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev Адрес доверенного ERC2771-форвардера (хранится в storage для поддержки upgrade)
    address private _trustedForwarder;

    event TrustedForwarderChanged(address indexed oldForwarder, address indexed newForwarder);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------------------
    // Инициализация
    // -------------------------------------------------------------------------

    /**
     * @notice Инициализация токена. Вызывается один раз через прокси.
     * @param name_             Название токена
     * @param symbol_           Символ токена
     * @param trustedForwarder_ Адрес доверенного форвардера для мета-транзакций
     * @param admin             Адрес первоначального администратора
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address trustedForwarder_,
        address admin
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE,        admin);
        _grantRole(BURNER_ROLE,        admin);
        _grantRole(UPGRADER_ROLE,      admin);

        _trustedForwarder = trustedForwarder_;
    }

    // -------------------------------------------------------------------------
    // Мета-транзакции (ERC2771)
    // -------------------------------------------------------------------------

    function trustedForwarder() public view returns (address) {
        return _trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == _trustedForwarder;
    }

    /**
     * @notice Обновить адрес доверенного форвардера (только DEFAULT_ADMIN_ROLE).
     */
    function setTrustedForwarder(address forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit TrustedForwarderChanged(_trustedForwarder, forwarder);
        _trustedForwarder = forwarder;
    }

    /**
     * @dev Если вызов от доверенного форвардера — извлекаем реального отправителя
     *      из последних 20 байт calldata (стандарт ERC2771).
     */
    function _msgSender() internal view override returns (address sender) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }

    function _msgData() internal view override returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender) && msg.data.length >= 20) {
            return msg.data[:msg.data.length - 20];
        }
        return msg.data;
    }

    // -------------------------------------------------------------------------
    // Mint / Burn
    // -------------------------------------------------------------------------

    function mint(address to, uint256 amount) external virtual onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // UUPS: только UPGRADER_ROLE может обновить реализацию
    // -------------------------------------------------------------------------

    function _authorizeUpgrade(address /*newImplementation*/)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}
