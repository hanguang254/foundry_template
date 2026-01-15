// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TransferWallet} from "../src/transferWallet.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TransferWalletTest is Test {
    TransferWallet public wallet;
    MockERC20 public token;

    address public user = address(0xBEEF);
    address public recipient1 = address(0xCAFE);
    address public recipient2 = address(0xD00D);

    receive() external payable {}

    function setUp() public {
        TransferWallet implementation = new TransferWallet();
        bytes memory data = abi.encodeCall(TransferWallet.initialize, (address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        wallet = TransferWallet(payable(address(proxy)));

        token = new MockERC20();
        wallet.setTokenAddress(address(token));
    }

    function test_DepositMainToken_IncreasesQuota() public {
        // 用例：主币存入后额度累加
        vm.deal(user, 5 ether);

        vm.prank(user);
        wallet.depositMainToken{value: 1 ether}();
        console2.log("quota after first deposit", wallet.depositMainTokenQuota(user));
        assertEq(wallet.depositMainTokenQuota(user), 1 ether);

        vm.prank(user);
        wallet.depositMainToken{value: 2 ether}();
        console2.log("quota after second deposit", wallet.depositMainTokenQuota(user));
        assertEq(wallet.depositMainTokenQuota(user), 3 ether);
    }

    function test_TransferMainToken_SendsAndUpdatesQuota() public {
        // 用例：主币批量转账成功并扣减额度
        vm.deal(user, 5 ether);

        vm.prank(user);
        wallet.depositMainToken{value: 5 ether}();
        console2.log("quota before transfer", wallet.depositMainTokenQuota(user));

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.prank(user);
        wallet.transferMainToken(recipients, amounts);

        console2.log("recipient1 balance", recipient1.balance);
        console2.log("recipient2 balance", recipient2.balance);
        console2.log("quota after transfer", wallet.depositMainTokenQuota(user));
        assertEq(wallet.depositMainTokenQuota(user), 2 ether);
        assertEq(recipient1.balance, 1 ether);
        assertEq(recipient2.balance, 2 ether);
    }

    function test_TransferMainToken_RevertsIfOverQuota() public {
        // 用例：转账总额超过额度时回滚
        vm.deal(user, 1 ether);

        vm.prank(user);
        wallet.depositMainToken{value: 1 ether}();
        console2.log("quota before over-quota transfer", wallet.depositMainTokenQuota(user));

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2 ether;

        vm.prank(user);
        vm.expectRevert("Address Insufficient deposit amount");
        wallet.transferMainToken(recipients, amounts);
    }

    function test_TransferMainToken_RevertsOnLengthMismatch() public {
        // 用例：收款地址与金额数组长度不一致时回滚
        vm.deal(user, 1 ether);

        vm.prank(user);
        wallet.depositMainToken{value: 1 ether}();
        console2.log("quota before length mismatch transfer", wallet.depositMainTokenQuota(user));

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 ether;
        amounts[1] = 0.5 ether;

        vm.prank(user);
        vm.expectRevert("Number of recipients must be equal to the number of amounts.");
        wallet.transferMainToken(recipients, amounts);
    }

    function test_DepositMainToken_ReceiveFunctionIncreasesQuota() public {
        // 用例：直接转账触发 receive，额度累加
        vm.deal(user, 1 ether);

        vm.prank(user);
        (bool success, ) = address(wallet).call{value: 0.4 ether}("");
        assertTrue(success);
        assertEq(wallet.depositMainTokenQuota(user), 0.4 ether);
    }

    function test_TransferMainToken_RevertsIfNoDeposit() public {
        // 用例：未存款直接转账会回滚
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(user);
        vm.expectRevert("Not deposit amount");
        wallet.transferMainToken(recipients, amounts);
    }

    function test_Withdraw_OnlyOwner() public {
        // 用例：仅 owner 可提现主币
        vm.deal(address(this), 0);
        vm.deal(user, 1 ether);

        vm.prank(user);
        wallet.depositMainToken{value: 1 ether}();
        console2.log("contract balance before withdraw", address(wallet).balance);

        wallet.withdraw(1 ether);
        console2.log("owner balance after withdraw", address(this).balance);
        assertEq(address(this).balance, 1 ether);
    }

    function test_Withdraw_RevertsForNonOwner() public {
        // 用例：非 owner 提现会回滚
        console2.log("non-owner", user);
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        wallet.withdraw(1);
    }

    function test_DepositLockToken_RevertsIfZeroAmount() public {
        // 用例：锁仓金额为 0 时回滚
        vm.expectRevert("amount = 0");
        wallet.depositlockToken(0);
    }

    function test_TransferToken_RevertsIfStillLocked() public {
        // 用例：锁仓期未到转账 ERC20 会回滚
        uint256 amount = 1000 ether;
        token.mint(address(this), amount);
        token.approve(address(wallet), amount);

        wallet.depositlockToken(amount);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.expectRevert("still locked");
        wallet.transferToken(recipients, amounts);
    }

    function test_TransferToken_RevertsOnLengthMismatch() public {
        // 用例：ERC20 转账数组长度不一致时回滚
        uint256 amount = 1000 ether;
        token.mint(address(this), amount);
        token.approve(address(wallet), amount);

        wallet.depositlockToken(amount);
        vm.warp(block.timestamp + 31 days);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vm.expectRevert("Number of recipients must be equal to the number of amounts.");
        wallet.transferToken(recipients, amounts);
    }

    function test_DepositLockToken_ThenTransferToken_AfterUnlock() public {
        // 用例：锁仓后到期可批量转账 ERC20，并清空锁仓时间
        uint256 amount = 1000 ether;
        token.mint(address(this), amount);
        token.approve(address(wallet), amount);

        wallet.depositlockToken(amount);
        console2.log("unlock time", wallet.unlockTime(address(this)));
        assertGt(wallet.unlockTime(address(this)), block.timestamp);

        vm.warp(block.timestamp + 31 days);
        console2.log("timestamp after warp", block.timestamp);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 200 ether;
        amounts[1] = 300 ether;

        wallet.transferToken(recipients, amounts);

        console2.log("recipient1 token", token.balanceOf(recipient1));
        console2.log("recipient2 token", token.balanceOf(recipient2));
        assertEq(token.balanceOf(recipient1), 200 ether);
        assertEq(token.balanceOf(recipient2), 300 ether);
        assertEq(wallet.unlockTime(address(this)), 0);
    }
}
