// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/OlegToken.sol";
import "../src/OlegTokenV2.sol";
import "../src/TokenFactory.sol";

/**
 * @title OlegTokenTest
 * @notice Тесты для OlegToken (UUPS), OlegTokenV2 (upgrade) и TokenFactory (EIP-1167).
 */
contract OlegTokenTest is Test {
    // -------------------------------------------------------------------------
    // Участники тестов
    // -------------------------------------------------------------------------
    address internal admin   = makeAddr("admin");
    address internal minter  = makeAddr("minter");
    address internal burner  = makeAddr("burner");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal forwarder = makeAddr("forwarder");

    // Ключ для подписи permit
    uint256 internal aliceKey;

    OlegToken  internal impl;
    OlegToken  internal token;   // прокси, задекорированный как OlegToken
    ERC1967Proxy internal proxy;

    TokenFactory internal factory;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        // Генерируем детерминированный ключ для alice
        aliceKey = uint256(keccak256(abi.encodePacked("alice")));
        alice = vm.addr(aliceKey);

        // Деплой реализации
        impl = new OlegToken();

        // Деплой прокси с инициализацией
        bytes memory initData = abi.encodeCall(
            OlegToken.initialize,
            ("OlegToken", "OTK", forwarder, admin)
        );
        proxy = new ERC1967Proxy(address(impl), initData);
        token = OlegToken(address(proxy));

        // Назначаем роли
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        vm.stopPrank();

        // Деплой фабрики
        factory = new TokenFactory(address(impl));
    }

    // =========================================================================
    // 1. УРОВНИ ДОСТУПА
    // =========================================================================

    function test_AdminHasAllRoles() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(),        admin));
        assertTrue(token.hasRole(token.BURNER_ROLE(),        admin));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(),      admin));
    }

    function test_MintOnlyMinter() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_MintRevertsForNonMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000e18);
    }

    function test_BurnOnlyBurner() public {
        vm.prank(minter);
        token.mint(alice, 500e18);

        vm.prank(burner);
        token.burn(alice, 200e18);
        assertEq(token.balanceOf(alice), 300e18);
    }

    function test_BurnRevertsForNonBurner() public {
        vm.prank(minter);
        token.mint(alice, 500e18);

        vm.prank(alice);
        vm.expectRevert();
        token.burn(alice, 100e18);
    }

    function test_GrantAndRevokeRole() public {
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), alice);
        assertTrue(token.hasRole(token.MINTER_ROLE(), alice));

        token.revokeRole(token.MINTER_ROLE(), alice);
        assertFalse(token.hasRole(token.MINTER_ROLE(), alice));
        vm.stopPrank();
    }

    // =========================================================================
    // 2. МЕТА-ТРАНЗАКЦИИ (ERC2771)
    // =========================================================================

    function test_TrustedForwarderSet() public view {
        assertEq(token.trustedForwarder(), forwarder);
        assertTrue(token.isTrustedForwarder(forwarder));
    }

    function test_SetTrustedForwarder() public {
        address newFwd = makeAddr("newForwarder");
        vm.prank(admin);
        token.setTrustedForwarder(newFwd);
        assertEq(token.trustedForwarder(), newFwd);
    }

    function test_SetTrustedForwarderRevertsForNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setTrustedForwarder(alice);
    }

    /**
     * @notice Симулируем мета-транзакцию: форвардер вызывает mint от имени admin.
     *         Реальный отправитель (admin) добавляется в конец calldata.
     */
    function test_MetaTransaction_MintViaForwarder() public {
        // Создаём calldata: mint(bob, 100) + адрес admin в конце (ERC2771)
        bytes memory innerCall = abi.encodeCall(OlegToken.mint, (bob, 100e18));
        bytes memory metaCalldata = abi.encodePacked(innerCall, admin);

        vm.prank(forwarder);
        (bool ok,) = address(token).call(metaCalldata);
        assertTrue(ok, "meta-tx failed");

        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_MetaTransaction_NonForwarderCannotSpoof() public {
        // Обычный пользователь НЕ является форвардером — suffix игнорируется,
        // _msgSender() вернёт alice, у которой нет MINTER_ROLE
        bytes memory innerCall = abi.encodeCall(OlegToken.mint, (bob, 100e18));
        bytes memory metaCalldata = abi.encodePacked(innerCall, admin);

        vm.prank(alice);
        (bool ok,) = address(token).call(metaCalldata);
        assertFalse(ok, "spoofed meta-tx should fail");
    }

    // =========================================================================
    // 3. PERMIT (ERC2612)
    // =========================================================================

    function test_Permit() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);

        uint256 value    = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce    = token.nonces(alice);

        // Формируем EIP-712 digest
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, bob, value, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        // Выполняем permit от имени любого — без газа от alice
        vm.prank(bob);
        token.permit(alice, bob, value, deadline, v, r, s);

        assertEq(token.allowance(alice, bob), value);
    }

    function test_PermitRevertsWithWrongSigner() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 bobKey   = uint256(keccak256(abi.encodePacked("bob")));

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, alice, bob, 500e18, token.nonces(alice), deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        // Подписываем bob'ом, но в permit указываем alice как owner
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digest);

        vm.expectRevert();
        token.permit(alice, bob, 500e18, deadline, v, r, s);
    }

    // =========================================================================
    // 4. UUPS UPGRADE
    // =========================================================================

    function test_UpgradeToV2() public {
        // Деплоим новую реализацию V2
        OlegTokenV2 implV2 = new OlegTokenV2();

        // Апгрейдим прокси
        vm.prank(admin);
        token.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(OlegTokenV2.initializeV2, (1_000_000e18))
        );

        OlegTokenV2 tokenV2 = OlegTokenV2(address(proxy));

        // Состояние сохранилось
        assertEq(tokenV2.name(),    "OlegToken");
        assertEq(tokenV2.symbol(),  "OTK");
        assertTrue(tokenV2.hasRole(tokenV2.DEFAULT_ADMIN_ROLE(), admin));

        // Новая функциональность работает
        assertEq(tokenV2.version(), "2.0.0");
        assertEq(tokenV2.cap(),     1_000_000e18);
    }

    function test_UpgradeRevertsForNonUpgrader() public {
        OlegTokenV2 implV2 = new OlegTokenV2();

        vm.prank(alice);
        vm.expectRevert();
        token.upgradeToAndCall(address(implV2), "");
    }

    function test_V2CapEnforced() public {
        OlegTokenV2 implV2 = new OlegTokenV2();

        vm.prank(admin);
        token.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(OlegTokenV2.initializeV2, (1000e18))
        );

        OlegTokenV2 tokenV2 = OlegTokenV2(address(proxy));

        vm.prank(admin);
        tokenV2.mint(alice, 1000e18); // ровно cap — ок

        vm.prank(admin);
        vm.expectRevert("OlegTokenV2: cap exceeded");
        tokenV2.mint(alice, 1); // превышение — revert
    }

    // =========================================================================
    // 5. FACTORY (EIP-1167)
    // =========================================================================

    function test_FactoryDeployToken() public {
        address cloneAddr = factory.deployToken("CloneToken", "CLN", address(0), admin);

        assertFalse(cloneAddr == address(0));
        assertEq(factory.tokensCount(), 1);
        assertEq(factory.tokenAt(0), cloneAddr);

        OlegToken clone = OlegToken(cloneAddr);
        assertEq(clone.name(),   "CloneToken");
        assertEq(clone.symbol(), "CLN");
        assertTrue(clone.hasRole(clone.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_FactoryDeployMultipleTokens() public {
        factory.deployToken("Token A", "TKA", address(0), admin);
        factory.deployToken("Token B", "TKB", address(0), admin);
        factory.deployToken("Token C", "TKC", address(0), admin);

        assertEq(factory.tokensCount(), 3);

        address[] memory all = factory.allTokens();
        assertEq(all.length, 3);

        // Каждый клон независим
        assertEq(OlegToken(all[0]).name(), "Token A");
        assertEq(OlegToken(all[1]).name(), "Token B");
        assertEq(OlegToken(all[2]).name(), "Token C");
    }

    function test_FactoryDeterministicDeploy() public {
        bytes32 salt = keccak256("my-salt");

        address predicted = factory.predictDeterministicAddress(salt);
        address deployed  = factory.deployTokenDeterministic(
            "DetToken", "DET", address(0), admin, salt
        );

        assertEq(predicted, deployed);
    }

    function test_FactoryClonesAreIsolated() public {
        address clone1 = factory.deployToken("TokenA", "TKA", address(0), admin);
        address clone2 = factory.deployToken("TokenB", "TKB", address(0), admin);

        // Минтим в первом клоне
        vm.prank(admin);
        OlegToken(clone1).mint(alice, 999e18);

        // Второй клон не затронут
        assertEq(OlegToken(clone1).balanceOf(alice), 999e18);
        assertEq(OlegToken(clone2).balanceOf(alice), 0);
    }

    function test_FactorySetImplementation() public {
        OlegTokenV2 implV2 = new OlegTokenV2();
        factory.setImplementation(address(implV2));
        assertEq(factory.implementation(), address(implV2));
    }

    function test_FactorySetImplementationRevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setImplementation(alice);
    }

    function test_FactoryDeployRevertsOnEmptyName() public {
        vm.expectRevert(TokenFactory.EmptyName.selector);
        factory.deployToken("", "SYM", address(0), admin);
    }

    function test_FactoryDeployRevertsOnZeroAdmin() public {
        vm.expectRevert(TokenFactory.ZeroAddress.selector);
        factory.deployToken("Name", "SYM", address(0), address(0));
    }

    // =========================================================================
    // 6. ОБЩИЕ ФУНКЦИИ ERC20
    // =========================================================================

    function test_Transfer() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.transfer(bob, 400e18);

        assertEq(token.balanceOf(alice), 600e18);
        assertEq(token.balanceOf(bob),   400e18);
    }

    function test_Approve_TransferFrom() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.approve(bob, 300e18);

        vm.prank(bob);
        token.transferFrom(alice, bob, 300e18);

        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(bob),   300e18);
    }
}
