// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TransferWalletV2} from "../src/TransferWalletV2.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 代币用于测试
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TransferWalletV2Test is Test {
    TransferWalletV2 public wallet;
    MockERC20 public usdt;
    MockERC20 public usdc;
    MockERC20 public dai;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public recipient1 = address(0x3);

    event TokenDepositLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 unlockTime
    );

    receive() external payable {}

    function setUp() public {
        console2.log("=== Setting up TransferWalletV2 Test ===");
        
        // 部署实现合约
        TransferWalletV2 implementation = new TransferWalletV2();
        
        // 部署代理合约
        bytes memory data = abi.encodeCall(TransferWalletV2.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        wallet = TransferWalletV2(payable(address(proxy)));

        // 部署测试代币
        usdt = new MockERC20("USDT", "USDT");
        usdc = new MockERC20("USDC", "USDC");
        dai = new MockERC20("DAI", "DAI");

        // 给测试用户铸造代币
        usdt.mint(user1, 10000 * 1e18);
        usdc.mint(user1, 10000 * 1e18);
        dai.mint(user1, 10000 * 1e18);
        
        usdt.mint(user2, 5000 * 1e18);

        console2.log("Proxy address:", address(wallet));
        console2.log("Implementation:", wallet.getImplementation());
        console2.log("Owner:", wallet.owner());
    }

    // ==================== 测试多代币锁仓功能 ====================

    function test_DepositLockToken_WithCustomLockDays() public {
        console2.log("\n=== Test: Deposit and Lock Token with Custom Days ===");
        
        uint256 lockAmount = 1000 * 1e18;
        uint256 lockDays = 90; // 锁定 90 天

        // 用户授权
        vm.startPrank(user1);
        usdt.approve(address(wallet), lockAmount);

        // 锁定 USDT
        uint256 unlockTimeBefore = block.timestamp + lockDays * 1 days;
        
        vm.expectEmit(true, true, false, true);
        emit TokenDepositLocked(user1, address(usdt), lockAmount, unlockTimeBefore);
        
        bool success = wallet.depositlockToken(address(usdt), lockAmount, lockDays);
        assertTrue(success);

        // 验证锁定信息
        (uint256 unlockTime, bool isLocked, uint256 remainingTime, uint256 lockedAmount) 
            = wallet.getTokenLockInfo(user1, address(usdt));
        
        console2.log("Unlock time:", unlockTime);
        console2.log("Is locked:", isLocked);
        console2.log("Remaining time (days):", remainingTime / 1 days);
        console2.log("Locked amount:", lockedAmount);

        assertEq(lockedAmount, lockAmount, "Locked amount mismatch");
        assertTrue(isLocked, "Should be locked");
        assertEq(remainingTime, lockDays * 1 days, "Remaining time mismatch");
        
        vm.stopPrank();
    }

    function test_DepositLockToken_MultipleTokens() public {
        console2.log("\n=== Test: Lock Multiple Different Tokens ===");
        
        vm.startPrank(user1);
        
        // 锁定 USDT - 30 天
        usdt.approve(address(wallet), 1000 * 1e18);
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
        
        // 锁定 USDC - 60 天
        usdc.approve(address(wallet), 2000 * 1e18);
        wallet.depositlockToken(address(usdc), 2000 * 1e18, 60);
        
        // 锁定 DAI - 90 天
        dai.approve(address(wallet), 3000 * 1e18);
        wallet.depositlockToken(address(dai), 3000 * 1e18, 90);
        
        vm.stopPrank();

        // 验证每种代币的锁定信息
        (, , uint256 usdtRemaining, uint256 usdtAmount) = wallet.getTokenLockInfo(user1, address(usdt));
        (, , uint256 usdcRemaining, uint256 usdcAmount) = wallet.getTokenLockInfo(user1, address(usdc));
        (, , uint256 daiRemaining, uint256 daiAmount) = wallet.getTokenLockInfo(user1, address(dai));

        console2.log("USDT locked:", usdtAmount, "remaining days:", usdtRemaining / 1 days);
        console2.log("USDC locked:", usdcAmount, "remaining days:", usdcRemaining / 1 days);
        console2.log("DAI locked:", daiAmount, "remaining days:", daiRemaining / 1 days);

        assertEq(usdtAmount, 1000 * 1e18);
        assertEq(usdcAmount, 2000 * 1e18);
        assertEq(daiAmount, 3000 * 1e18);
        assertEq(usdtRemaining, 30 days);
        assertEq(usdcRemaining, 60 days);
        assertEq(daiRemaining, 90 days);
    }

    function test_DepositLockToken_AccumulateAmount() public {
        console2.log("\n=== Test: Accumulate Lock Amount ===");
        
        vm.startPrank(user1);
        
        // 第一次锁定
        usdt.approve(address(wallet), 1000 * 1e18);
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
        
        // 第二次锁定（累加）
        usdt.approve(address(wallet), 500 * 1e18);
        wallet.depositlockToken(address(usdt), 500 * 1e18, 30);
        
        vm.stopPrank();

        (, , , uint256 lockedAmount) = wallet.getTokenLockInfo(user1, address(usdt));
        
        console2.log("Total locked amount:", lockedAmount);
        assertEq(lockedAmount, 1500 * 1e18, "Should accumulate amounts");
    }

    // ==================== 测试提取功能 ====================

    function test_WithdrawLockedToken_Success() public {
        console2.log("\n=== Test: Withdraw Locked Token After Unlock ===");
        
        uint256 lockAmount = 1000 * 1e18;
        uint256 lockDays = 30;

        // 用户锁定代币
        vm.startPrank(user1);
        usdt.approve(address(wallet), lockAmount);
        wallet.depositlockToken(address(usdt), lockAmount, lockDays);
        
        // 快进时间到解锁日期
        vm.warp(block.timestamp + lockDays * 1 days);
        
        // 验证已解锁
        (, bool isLocked, , ) = wallet.getTokenLockInfo(user1, address(usdt));
        assertFalse(isLocked, "Should be unlocked");

        // 提取代币
        uint256 balanceBefore = usdt.balanceOf(user1);
        wallet.withdrawLockedToken(address(usdt), 0); // 0 表示提取全部
        uint256 balanceAfter = usdt.balanceOf(user1);

        console2.log("Balance before:", balanceBefore);
        console2.log("Balance after:", balanceAfter);
        console2.log("Withdrawn:", balanceAfter - balanceBefore);

        assertEq(balanceAfter - balanceBefore, lockAmount, "Should receive all locked tokens");
        
        // 验证锁定记录已清除
        (, , , uint256 remainingLocked) = wallet.getTokenLockInfo(user1, address(usdt));
        assertEq(remainingLocked, 0, "Should have no locked tokens");
        
        vm.stopPrank();
    }

    function test_WithdrawLockedToken_PartialWithdraw() public {
        console2.log("\n=== Test: Partial Withdraw ===");
        
        uint256 lockAmount = 1000 * 1e18;
        uint256 withdrawAmount = 400 * 1e18;

        vm.startPrank(user1);
        usdt.approve(address(wallet), lockAmount);
        wallet.depositlockToken(address(usdt), lockAmount, 30);
        
        // 快进到解锁时间
        vm.warp(block.timestamp + 30 days);
        
        // 部分提取
        wallet.withdrawLockedToken(address(usdt), withdrawAmount);
        
        // 验证剩余锁定数量
        (, , , uint256 remainingLocked) = wallet.getTokenLockInfo(user1, address(usdt));
        assertEq(remainingLocked, lockAmount - withdrawAmount, "Should have remaining locked tokens");
        
        vm.stopPrank();
    }

    function test_WithdrawLockedToken_RevertWhenStillLocked() public {
        console2.log("\n=== Test: Revert When Still Locked ===");
        
        vm.startPrank(user1);
        usdt.approve(address(wallet), 1000 * 1e18);
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
        
        // 尝试在锁定期内提取（应该失败）
        vm.expectRevert("Tokens still locked");
        wallet.withdrawLockedToken(address(usdt), 0);
        
        vm.stopPrank();
    }

    function test_WithdrawLockedToken_RevertWhenNoLock() public {
        console2.log("\n=== Test: Revert When No Locked Tokens ===");
        
        vm.prank(user2);
        vm.expectRevert("You have no locked tokens for this token address");
        wallet.withdrawLockedToken(address(usdt), 0);
    }

    // ==================== 测试 Owner 提取功能 ====================

    function test_WithdrawLockedTokenByOwner_Success() public {
        console2.log("\n=== Test: Owner Withdraw For User ===");
        
        uint256 lockAmount = 1000 * 1e18;

        // 用户锁定代币
        vm.startPrank(user1);
        usdt.approve(address(wallet), lockAmount);
        wallet.depositlockToken(address(usdt), lockAmount, 30);
        vm.stopPrank();

        // 快进到解锁时间
        vm.warp(block.timestamp + 30 days);

        // Owner 帮助用户提取
        uint256 user1BalanceBefore = usdt.balanceOf(user1);
        
        vm.prank(owner);
        wallet.withdrawLockedTokenByOwner(user1, address(usdt), 0);
        
        uint256 user1BalanceAfter = usdt.balanceOf(user1);

        console2.log("User balance before:", user1BalanceBefore);
        console2.log("User balance after:", user1BalanceAfter);

        // 验证代币发给了用户，不是 owner
        assertEq(user1BalanceAfter - user1BalanceBefore, lockAmount);
        assertEq(usdt.balanceOf(owner), 0, "Owner should not receive tokens");
    }

    function test_WithdrawLockedTokenByOwner_RevertWhenNotOwner() public {
        console2.log("\n=== Test: Revert When Not Owner ===");
        
        vm.startPrank(user1);
        usdt.approve(address(wallet), 1000 * 1e18);
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        // 非 owner 尝试调用（应该失败）
        vm.prank(user2);
        vm.expectRevert();
        wallet.withdrawLockedTokenByOwner(user1, address(usdt), 0);
    }

    // ==================== 测试查询功能 ====================

    function test_GetTokenLockInfo_NoLock() public {
        console2.log("\n=== Test: Query Info For Unlocked Token ===");
        
        (uint256 unlockTime, bool isLocked, uint256 remainingTime, uint256 lockedAmount) 
            = wallet.getTokenLockInfo(user1, address(usdt));

        console2.log("Unlock time:", unlockTime);
        console2.log("Is locked:", isLocked);
        console2.log("Remaining time:", remainingTime);
        console2.log("Locked amount:", lockedAmount);

        assertEq(unlockTime, 0);
        assertFalse(isLocked);
        assertEq(remainingTime, 0);
        assertEq(lockedAmount, 0);
    }

    function test_GetTokenBalance() public {
        console2.log("\n=== Test: Get Token Balance ===");
        
        // 用户锁定代币
        vm.startPrank(user1);
        usdt.approve(address(wallet), 1000 * 1e18);
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
        vm.stopPrank();

        // 查询合约中的 USDT 余额
        uint256 balance = wallet.getTokenBalance(address(usdt));
        console2.log("Contract USDT balance:", balance);
        
        assertEq(balance, 1000 * 1e18);
    }

    // ==================== 测试错误情况 ====================

    function test_DepositLockToken_RevertWhenZeroAmount() public {
        console2.log("\n=== Test: Revert When Zero Amount ===");
        
        vm.startPrank(user1);
        usdt.approve(address(wallet), 1000 * 1e18);
        
        vm.expectRevert("amount = 0");
        wallet.depositlockToken(address(usdt), 0, 30);
        
        vm.stopPrank();
    }

    function test_DepositLockToken_RevertWhenZeroLockDays() public {
        console2.log("\n=== Test: Revert When Zero Lock Days ===");
        
        vm.startPrank(user1);
        usdt.approve(address(wallet), 1000 * 1e18);
        
        vm.expectRevert("Lock days must be greater than 0");
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 0);
        
        vm.stopPrank();
    }

    function test_DepositLockToken_RevertWhenInvalidTokenAddress() public {
        console2.log("\n=== Test: Revert When Invalid Token Address ===");
        
        vm.prank(user1);
        vm.expectRevert("Invalid token address");
        wallet.depositlockToken(address(0), 1000 * 1e18, 30);
    }

    function test_DepositLockToken_RevertWhenInsufficientAllowance() public {
        console2.log("\n=== Test: Revert When Insufficient Allowance ===");
        
        vm.prank(user1);
        // 没有授权就尝试锁定
        vm.expectRevert("ERC20: insufficient allowance");
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
    }

    // ==================== 测试升级功能 ====================

    function test_UpgradeContract() public {
        console2.log("\n=== Test: Upgrade Contract ===");
        
        // 部署新的实现合约
        TransferWalletV2 newImplementation = new TransferWalletV2();
        
        address oldImplementation = wallet.getImplementation();
        console2.log("Old implementation:", oldImplementation);
        
        // 升级
        vm.prank(owner);
        wallet.upgradeTo(address(newImplementation));
        
        address newImplementationAddr = wallet.getImplementation();
        console2.log("New implementation:", newImplementationAddr);
        
        assertEq(newImplementationAddr, address(newImplementation));
        assertTrue(oldImplementation != newImplementationAddr);
        
        // 验证升级后仍然可以使用
        vm.startPrank(user1);
        usdt.approve(address(wallet), 1000 * 1e18);
        wallet.depositlockToken(address(usdt), 1000 * 1e18, 30);
        vm.stopPrank();
        
        (, , , uint256 lockedAmount) = wallet.getTokenLockInfo(user1, address(usdt));
        assertEq(lockedAmount, 1000 * 1e18);
    }

    // ==================== 测试主币功能（向后兼容） ====================

    function test_DepositMainToken() public {
        console2.log("\n=== Test: Deposit Main Token (ETH) ===");
        
        vm.deal(user1, 10 ether);
        
        vm.prank(user1);
        wallet.depositMainToken{value: 1 ether}();
        
        uint256 quota = wallet.depositMainTokenQuota(user1);
        console2.log("User1 quota:", quota);
        
        assertEq(quota, 1 ether);
        assertEq(address(wallet).balance, 1 ether);
    }

    function test_MainTokenBalanceOf() public {
        console2.log("\n=== Test: Main Token Balance ===");
        
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        wallet.depositMainToken{value: 2 ether}();
        
        uint256 balance = wallet.MainTokenBalanceOf();
        console2.log("Contract ETH balance:", balance);
        
        assertEq(balance, 2 ether);
    }
}
