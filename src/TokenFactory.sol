// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenFactory
 * @notice Factory-контракт, создающий минимальные прокси (EIP-1167) для OlegToken.
 *
 * Принцип работы:
 *   - Владелец фабрики устанавливает адрес реализации (implementation).
 *   - Любой вызывающий может развернуть новый клон через deployToken().
 *   - Каждый клон — независимый ERC20-токен с собственным хранилищем,
 *     но разделяет байткод с реализацией (экономия газа ~10x).
 */
contract TokenFactory is Ownable {
    using Clones for address;

    /// @dev Адрес реализации OlegToken, которую клонируем
    address public implementation;

    /// @dev Список всех созданных клонов
    address[] private _tokens;

    event TokenDeployed(
        address indexed token,
        address indexed deployer,
        string  name,
        string  symbol
    );

    event ImplementationUpdated(address indexed oldImpl, address indexed newImpl);

    error ZeroAddress();
    error EmptyName();
    error EmptySymbol();

    constructor(address implementation_) Ownable(msg.sender) {
        if (implementation_ == address(0)) revert ZeroAddress();
        implementation = implementation_;
    }

    // -------------------------------------------------------------------------
    // Управление реализацией
    // -------------------------------------------------------------------------

    /**
     * @notice Обновить адрес реализации для новых клонов (только owner).
     *         Уже развёрнутые клоны не затрагиваются.
     */
    function setImplementation(address newImpl) external onlyOwner {
        if (newImpl == address(0)) revert ZeroAddress();
        emit ImplementationUpdated(implementation, newImpl);
        implementation = newImpl;
    }

    // -------------------------------------------------------------------------
    // Развёртывание клонов
    // -------------------------------------------------------------------------

    /**
     * @notice Создать новый ERC20-токен как клон реализации.
     * @param name_             Название токена
     * @param symbol_           Символ токена
     * @param trustedForwarder_ Адрес ERC2771-форвардера (address(0) — отключить)
     * @param admin             Адрес администратора нового токена
     * @return token            Адрес развёрнутого клона
     */
    function deployToken(
        string  memory name_,
        string  memory symbol_,
        address        trustedForwarder_,
        address        admin
    ) external returns (address token) {
        if (bytes(name_).length   == 0) revert EmptyName();
        if (bytes(symbol_).length == 0) revert EmptySymbol();
        if (admin == address(0))        revert ZeroAddress();

        token = implementation.clone();

        // Вызываем initialize на клоне
        (bool ok, bytes memory err) = token.call(
            abi.encodeWithSignature(
                "initialize(string,string,address,address)",
                name_,
                symbol_,
                trustedForwarder_,
                admin
            )
        );
        require(ok, _getRevertMsg(err));

        _tokens.push(token);
        emit TokenDeployed(token, msg.sender, name_, symbol_);
    }

    /**
     * @notice Создать клон с детерминированным адресом (CREATE2).
     * @param salt  Произвольный соль для определения адреса
     */
    function deployTokenDeterministic(
        string  memory name_,
        string  memory symbol_,
        address        trustedForwarder_,
        address        admin,
        bytes32        salt
    ) external returns (address token) {
        if (bytes(name_).length   == 0) revert EmptyName();
        if (bytes(symbol_).length == 0) revert EmptySymbol();
        if (admin == address(0))        revert ZeroAddress();

        token = implementation.cloneDeterministic(salt);

        (bool ok, bytes memory err) = token.call(
            abi.encodeWithSignature(
                "initialize(string,string,address,address)",
                name_,
                symbol_,
                trustedForwarder_,
                admin
            )
        );
        require(ok, _getRevertMsg(err));

        _tokens.push(token);
        emit TokenDeployed(token, msg.sender, name_, symbol_);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Количество созданных токенов
    function tokensCount() external view returns (uint256) {
        return _tokens.length;
    }

    /// @notice Адрес клона по индексу
    function tokenAt(uint256 index) external view returns (address) {
        return _tokens[index];
    }

    /// @notice Все адреса клонов
    function allTokens() external view returns (address[] memory) {
        return _tokens;
    }

    /**
     * @notice Предсказать адрес детерминированного клона до деплоя.
     */
    function predictDeterministicAddress(bytes32 salt) external view returns (address) {
        return implementation.predictDeterministicAddress(salt, address(this));
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
        if (returnData.length < 68) return "TokenFactory: call failed";
        assembly {
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string));
    }
}
