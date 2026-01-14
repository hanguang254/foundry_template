// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";



contract TransferWalletV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // #主币额度
    mapping (address => uint256) public depositMainTokenQuota;
    //锁仓映射
    mapping (address => uint256) public unlockTime;

    address public TokenAddress;
    bytes32 public test= "test";

    event Withdraw(address,uint);
    event Deposit(address,uint);
    event Transfer(address[] ,uint256[] );
    event DepositLocked(
        address indexed user,
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

    // ReentrancyGuardUpgradeable 的 nonReentrant 修饰符已经通过继承获得
    // 可以直接使用

    /**
     * @dev 存入并锁仓 ERC20 Token
     * @param amount 要存入的 Token 数量，必须大于 0
     * @return 操作是否成功
     * @notice Token 将被锁仓 30 天，在此期间无法提取
     * @notice 调用前需要先授权合约足够的 Token 额度
     */
    function depositlockToken(uint256 amount) external returns (bool) {
        require(amount > 0, "amount = 0");
        require(TokenAddress != address(0), "Token address not set");
        uint256 nowTime = block.timestamp;
        unlockTime[msg.sender] = nowTime + 30 days; // 锁仓一个月

        IERC20 token = IERC20(TokenAddress);

        // 确保授权充足（可选但强烈推荐）
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

        emit DepositLocked(msg.sender, amount, unlockTime[msg.sender]);

        return true;
    }

    /**
     * @dev 设置 ERC20 Token 合约地址
     * @param tokenAddress Token 合约地址
     * @notice 只有合约所有者可以调用此函数
     */
    function setTokenAddress(address tokenAddress) external onlyOwner {
        TokenAddress = tokenAddress;
    }
    
    /**
     * @dev 获取合约中 ERC20 Token 的余额
     * @return 合约持有的 Token 数量
     */
    function TokenBalanceOf() public view returns (uint256) {
        require(TokenAddress != address(0), "Token address not set");
        IERC20 token = IERC20(TokenAddress);
        return token.balanceOf(address(this));
    }
    
    /**
     * @dev 批量转账 ERC20 Token（仅限 owner 调用）
     * @param recipients 接收者地址数组
     * @param amounts 对应的转账数量数组
     * @return 操作是否成功
     * @notice 只有合约所有者可以调用
     * @notice 调用者必须已解锁（锁仓时间已过）
     * @notice recipients 和 amounts 数组长度必须相等
     */
    function transferToken(address[] memory recipients,uint256[] memory amounts) external onlyOwner  returns (bool) {
        uint256 balance = TokenBalanceOf();
        require(balance != 0,"Token balance is 0");
        uint256 totalAmount = 0;
        uint amountlength = amounts.length;
        for (uint i= 0;i<amountlength;){
            totalAmount += amounts[i];
            unchecked{
                i++;
            }
        }
        require(totalAmount>0,"amount cant be 0");
        // ✅ 正确的时间判断
        require(block.timestamp >= unlockTime[msg.sender], "still locked");
        unlockTime[msg.sender] = 0;
        _batchTransferToken(recipients, amounts);
        return true;
    }

    /**
     * @dev 内部函数：批量转账 ERC20 Token
     * @param recipients 接收者地址数组
     * @param amounts 对应的转账数量数组
     * @return 操作是否成功
     * @notice 此函数会验证数组长度是否匹配，并逐个执行转账
     */
    function _batchTransferToken(address[] memory recipients,uint256[] memory amounts) internal returns (bool){
        require(recipients.length == amounts.length, "Number of recipients must be equal to the number of amounts.");
        IERC20 token = IERC20(TokenAddress);
        uint addresslength  = recipients.length;
        for(uint i = 0 ;i<addresslength;){
            bool success = token.transfer(recipients[i], amounts[i]);
            require(success, "Token transfer failed");
            unchecked{
                i++;
            }
        }
        emit Transfer(recipients,amounts);
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
