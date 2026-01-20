// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";



contract TransferWalletV3 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // #主币额度
    mapping (address => uint256) public depositMainTokenQuota;

    // 多代币锁仓支持
    // user => token => unlockTime
    mapping(address => mapping(address => uint256)) public tokenUnlockTime;
    // user => token => locked amount
    mapping(address => mapping(address => uint256)) public tokenLockedAmount;

    event Withdraw(address,uint);
    event Deposit(address,uint);
    event Transfer(address[] ,uint256[] );
    event DepositLocked(
        address indexed user,
        uint256 amount,
        uint256 unlockTime
    );
    event TokenDepositLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 unlockTime
    );
    /**
     * @dev 代理合约初始化事件
     * @param proxy 代理合约地址
     * @param implementation 实现合约地址
     * @param owner 所有者地址
     */
    event ProxyInitialized(
        address indexed proxy,
        address indexed implementation,
        address indexed owner
    );


    /**
     * @dev 初始化可升级合约，设置初始 owner 并初始化重入保护
     * @param initialOwner 初始合约所有者地址，必须不为零地址（通常是部署者地址）
     * @notice 此函数只能调用一次，通过 initializer 修饰符保证
     */
    function initialize(address initialOwner) public initializer {
        // 确保 initialOwner 不为零地址
        require(initialOwner != address(0), "TransferWallet: owner cannot be zero address");

        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Ownable_init();
        // 设置正确的 owner（因为 __Ownable_init() 会将 msg.sender 设为 owner，在代理合约中 msg.sender 是代理合约本身）
        _transferOwnership(initialOwner);
        // address(this) 在 delegatecall 场景下是 Proxy 地址
        // _getImplementation() 来自 ERC1967Upgrade（UUPSUpgradeable 继承包含）
        emit ProxyInitialized(address(this), _getImplementation(), initialOwner);
    }

    

    /**
     * @dev 存入并锁仓指定的 ERC20 Token（新版本，支持任意代币和自定义锁定期）
     * @param tokenAddress 要锁定的代币合约地址
     * @param amount 要存入的 Token 数量，必须大于 0
     * @param lockDays 锁定天数，必须大于 0
     * @return 操作是否成功
     * @notice 调用前需要先授权合约足够的 Token 额度
     * @notice 同一用户可以锁定多种不同的代币
     * @notice 如果已有锁定记录，新的锁定期将从当前时间开始计算
     */
    function depositlockToken(address tokenAddress, uint256 amount, uint256 lockDays) nonReentrant external returns (bool) {
        require(amount > 0, "amount = 0");
        require(tokenAddress != address(0), "Invalid token address");
        require(lockDays > 0, "Lock days must be greater than 0");
        
        uint256 nowTime = block.timestamp;
        uint256 lockDuration = lockDays * 1 days;
        uint256 newUnlockTime = nowTime + lockDuration;
        
        // 如果已有锁定记录，新的解锁时间必须 >= 当前解锁时间
        uint256 currentUnlockTime = tokenUnlockTime[msg.sender][tokenAddress];
        if (currentUnlockTime > 0 && newUnlockTime < currentUnlockTime) {
            // 使用当前解锁时间（不允许缩短锁定期）
            newUnlockTime = currentUnlockTime;
        }
        
        tokenUnlockTime[msg.sender][tokenAddress] = newUnlockTime;
        tokenLockedAmount[msg.sender][tokenAddress] += amount;

        IERC20 token = IERC20(tokenAddress);

        // 确保授权充足
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "ERC20: insufficient allowance"
        );

        bool success = token.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "transfer failed");

        emit TokenDepositLocked(msg.sender, tokenAddress, amount, tokenUnlockTime[msg.sender][tokenAddress]);

        return true;
    }

    /**
     * @dev 查询指定用户和代币的锁定信息（新版本，支持任意代币）
     * @param user 要查询的用户地址
     * @param tokenAddress 要查询的代币合约地址
     * @return unlockTimestamp Token 解锁时间戳（Unix 时间），如果为 0 表示未锁定
     * @return isLocked 是否仍在锁定期内
     * @return remainingTime 剩余锁定时间（秒），如果已解锁则为 0
     * @return lockedAmount 锁定的代币数量
     */
    function getTokenLockInfo(address user, address tokenAddress) external view returns (
        uint256 unlockTimestamp,
        bool isLocked,
        uint256 remainingTime,
        uint256 lockedAmount
    ) {
        unlockTimestamp = tokenUnlockTime[user][tokenAddress];
        lockedAmount = tokenLockedAmount[user][tokenAddress];
        
        if (unlockTimestamp == 0) {
            // 未设置锁定时间
            isLocked = false;
            remainingTime = 0;
        } else if (block.timestamp >= unlockTimestamp) {
            // 已解锁
            isLocked = false;
            remainingTime = 0;
        } else {
            // 仍在锁定期内
            isLocked = true;
            remainingTime = unlockTimestamp - block.timestamp;
        }
        
        return (unlockTimestamp, isLocked, remainingTime, lockedAmount);
    }
    
    /**
     * @dev 查询合约中指定代币的余额
     * @param tokenAddress 要查询的代币合约地址
     * @return 合约持有的指定 Token 数量
     */
    function getTokenBalance(address tokenAddress) public view returns (uint256) {
        require(tokenAddress != address(0), "Invalid token address");
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }
    
    /**
     * @dev 提取已解锁的代币（用户自己提取）
     * @param tokenAddress 要提取的代币合约地址
     * @param amount 要提取的数量，如果为 0 则提取全部
     * @return 操作是否成功
     * @notice 只有之前锁定过代币的用户才能提取
     * @notice 只有锁定期已过才能提取
     * @notice 提取数量不能超过锁定的数量
     */
    function withdrawLockedToken(address tokenAddress, uint256 amount) external nonReentrant returns (bool) {
        require(tokenAddress != address(0), "Invalid token address");
        
        // 检查调用者是否锁定过代币
        uint256 lockedAmount = tokenLockedAmount[msg.sender][tokenAddress];
        require(lockedAmount > 0, "You have no locked tokens for this token address");
        
        // 检查是否已解锁
        uint256 unlockTimestamp = tokenUnlockTime[msg.sender][tokenAddress];
        require(unlockTimestamp != 0, "No lock record found");
        require(block.timestamp >= unlockTimestamp, "Tokens still locked");
        
        // 确定提取数量
        uint256 withdrawAmount = amount;
        if (amount == 0) {
            // 提取全部
            withdrawAmount = lockedAmount;
        } else {
            require(amount <= lockedAmount, "Insufficient locked amount");
        }
        
        // 更新锁定数量
        tokenLockedAmount[msg.sender][tokenAddress] -= withdrawAmount;
        
        // 如果全部提取完毕，清除解锁时间
        if (tokenLockedAmount[msg.sender][tokenAddress] == 0) {
            tokenUnlockTime[msg.sender][tokenAddress] = 0;
        }
        
        // 转账代币给用户
        IERC20 token = IERC20(tokenAddress);
        bool success = token.transfer(msg.sender, withdrawAmount);
        require(success, "Token transfer failed");
        
        return true;
    }

    /**
     * @dev Owner 帮助用户提取已解锁的代币（紧急情况使用）
     * @param user 用户地址
     * @param tokenAddress 要提取的代币合约地址
     * @param amount 要提取的数量，如果为 0 则提取全部
     * @return 操作是否成功
     * @notice 只有合约所有者可以调用
     * @notice 只能提取已解锁的代币
     * @notice 代币会发送给用户本人，不是 owner
     */
    function withdrawLockedTokenByOwner(address user, address tokenAddress, uint256 amount) external onlyOwner  returns (bool) {
        require(user != address(0), "Invalid user address");
        require(tokenAddress != address(0), "Invalid token address");
        
        // 检查用户是否锁定过代币
        uint256 lockedAmount = tokenLockedAmount[user][tokenAddress];
        require(lockedAmount > 0, "User has no locked tokens for this token address");
        
        // 检查是否已解锁
        uint256 unlockTimestamp = tokenUnlockTime[user][tokenAddress];
        require(unlockTimestamp != 0, "No lock record found");
        require(block.timestamp >= unlockTimestamp, "Tokens still locked");
        
        // 确定提取数量
        uint256 withdrawAmount = amount;
        if (amount == 0) {
            // 提取全部
            withdrawAmount = lockedAmount;
        } else {
            require(amount <= lockedAmount, "Insufficient locked amount");
        }
        
        // 更新锁定数量
        tokenLockedAmount[user][tokenAddress] -= withdrawAmount;
        
        // 如果全部提取完毕，清除解锁时间
        if (tokenLockedAmount[user][tokenAddress] == 0) {
            tokenUnlockTime[user][tokenAddress] = 0;
        }
        
        // 转账代币给用户（不是 owner）
        IERC20 token = IERC20(tokenAddress);
        bool success = token.transfer(user, withdrawAmount);
        require(success, "Token transfer failed");
        
        return true;
    }

    /**
     * @dev 计算指定代币的所有用户总锁定量
     * @param tokenAddress 要查询的代币合约地址
     * @param users 用户地址数组（需要提供所有可能锁定该代币的用户）
     * @return 所有用户的总锁定数量
     * @notice 需要传入所有锁定该代币的用户地址，否则计算不准确
     */
    function getTotalLockedAmount(address tokenAddress, address[] memory users) public view returns (uint256) {
        uint256 totalLocked = 0;
        for (uint i = 0; i < users.length; i++) {
            totalLocked += tokenLockedAmount[users[i]][tokenAddress];
        }
        return totalLocked;
    }

    /**
     * @dev Owner 提取未锁定的代币（意外转入或剩余的代币）
     * @param tokenAddress 要提取的代币合约地址
     * @param amount 要提取的数量
     * @param lockedUsers 所有锁定该代币的用户地址数组
     * @return 操作是否成功
     * @notice 只有合约所有者可以调用
     * @notice 只能提取"未被用户锁定"的代币余额
     * @notice 代币会发送给 owner
     * @notice 必须提供所有锁定该代币的用户地址，以确保不会误提取用户锁定的代币
     */
    function withdrawUnlockedTokenByOwner(
        address tokenAddress, 
        uint256 amount, 
        address[] memory lockedUsers
    ) external onlyOwner  returns (bool) {
        require(tokenAddress != address(0), "Invalid token address");
        
        // 获取合约中该代币的总余额
        IERC20 token = IERC20(tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance > 0, "No tokens in contract");
        
        // 计算所有用户的总锁定量
        uint256 totalLocked = getTotalLockedAmount(tokenAddress, lockedUsers);
        
        // 可提取余额 = 合约总余额 - 用户总锁定量
        uint256 availableBalance = contractBalance - totalLocked;
        require(availableBalance > 0, "No unlocked tokens available");
        require(amount <= availableBalance, "Amount exceeds available balance");
        
        // 转账代币给 owner
        bool success = token.transfer(msg.sender, amount);
        require(success, "Token transfer failed");
        
        return true;
    }
    

    /**
     * @dev 获取合约的主币（ETH/BNB）余额
     * @return 合约持有的主币数量（wei）
     */
    function MainTokenBalanceOf()external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 内部函数：获取指定地址的主币存款额度
     * @param from 要查询的地址
     * @return 该地址的存款额度
     */
    function getMainTokenQuota(address from) view internal returns(uint256){
        return depositMainTokenQuota[from];
    }

    /**
     * @dev 存入主币（ETH/BNB）
     * @return sender 存款者地址
     * @return 本次存款金额
     * @notice 使用 nonReentrant 修饰符防止重入攻击
     * @notice 可以通过 payable 函数或 receive/fallback 函数调用
     */
    function depositMainToken() payable public  nonReentrant returns(address,uint256){
        address sender = msg.sender;
        uint256 quota = getMainTokenQuota(sender);
        if(quota == 0){
            depositMainTokenQuota[sender] = msg.value;  
        }else {
            depositMainTokenQuota[sender] = msg.value+quota; 
        }
        emit Deposit(sender,msg.value);
        return (sender,msg.value);
    }

    /**
     * @dev 批量转账主币（ETH/BNB）
     * @param recipients 接收者地址数组
     * @param amounts 对应的转账数量数组（wei）
     * @return 操作是否成功
     * @notice 转账总额不能超过调用者的存款额度
     * @notice recipients 和 amounts 数组长度必须相等
     * @notice 转账成功后，会从调用者的存款额度中扣除相应金额
     */
    function transferMainToken(address[] memory recipients,uint256[] memory amounts) external  returns (bool) {
        address sender = msg.sender;
        uint256 quota = getMainTokenQuota(sender);
        require(quota != 0,"Not deposit amount");
        uint256 totalAmount = 0;
        uint amountlength = amounts.length;
        for (uint i= 0;i<amountlength;){
            totalAmount += amounts[i];
            unchecked{
                i++;
            }
        }
        require(totalAmount<=quota,"Address Insufficient deposit amount");
		depositMainTokenQuota[sender]=quota-totalAmount;
        _batchTransferMainToken(recipients, amounts);
        return true;
    }

    /**
     * @dev 内部函数：批量转账主币（ETH/BNB）
     * @param recipients 接收者地址数组
     * @param amounts 对应的转账数量数组（wei）
     * @return 操作是否成功
     * @notice 使用 call 方式转账，会触发接收者的 receive 或 fallback 函数
     * @notice 如果转账失败，整个交易会回滚
     */
    function _batchTransferMainToken(address[] memory recipients,uint256[] memory amounts) internal returns (bool){
        require(recipients.length == amounts.length, "Number of recipients must be equal to the number of amounts.");
        uint addresslength  = recipients.length;
        for(uint i = 0 ;i<addresslength;){
            (bool callSuccess, ) = recipients[i].call{value: amounts[i]}("");
            require(callSuccess,"transfer success");
            unchecked{
                i++;
            }
        }
        return true;
    }

    /**
     * @dev 提取主币（仅限 owner）
     * @param amount 要提取的主币数量（wei）
     * @return 操作是否成功
     * @notice 只有合约所有者可以调用此函数
     * @notice 用于紧急提取合约中的主币
     */
    function withdraw(uint256 amount) external onlyOwner returns (bool){
        (bool callSuccess, ) = payable(msg.sender).call{value: amount}("");
        require(callSuccess, "withdraw failed");
        emit Withdraw(msg.sender,amount);
        return true;
    }

    /**
     * @dev 回退函数：当调用不存在的函数时，自动存入主币
     * @notice 任何发送到合约的主币都会自动存入
     */
    fallback() external payable {
        depositMainToken();
    }

    /**
     * @dev 接收函数：当直接向合约发送主币时，自动存入
     * @notice 任何发送到合约的主币都会自动存入
     */
    receive() external payable {
        depositMainToken();
    }

    /**
     * @dev 获取当前实现合约地址（用于区块浏览器识别代理合约）
     * @return 实现合约地址
     * @notice 此函数帮助区块浏览器识别这是一个代理合约
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @dev 授权升级函数，只有 owner 可以升级合约
     * @param newImplementation 新的实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 存储间隙，用于未来升级时添加新的状态变量
     * @notice 可升级合约必须包含存储间隙，防止存储布局冲突
     * @notice OwnableUpgradeable 和 ReentrancyGuardUpgradeable 已经各自包含 49 个槽的间隙
     * @notice 这里添加额外的间隙以容纳本合约的状态变量（mappings 和 address）
     */
    uint256[47] private __gap;
}
