# CREATE2 多链部署快速指南

## ✅ 已完成

已成功创建使用 CREATE2 的多链部署脚本，确保在不同链上获得相同的合约地址！

## 🚀 快速开始

### 1. 修改 Salt 值（超级简单！）

打开 `script/DeployTransferWalletCreate2.s.sol`，找到这两行：

```solidity
string constant IMPLEMENTATION_SALT_STRING = "test_shahai_implementation";
string constant PROXY_SALT_STRING = "test_shahai_proxy";
```

改成你喜欢的任何字符串：

```solidity
string constant IMPLEMENTATION_SALT_STRING = "my_awesome_project_impl";
string constant PROXY_SALT_STRING = "my_awesome_project_proxy";
```

### 2. 设置环境变量并测试

```bash
export PRIVATE_KEY=your_private_key_here
export TEST_RPC_URL=your_rpc_url
export ETHERSCAN_API_KEY=your_api_key

# 查看预期地址
forge script script/DeployTransferWalletCreate2.s.sol
```

会显示：
```
Predicted Implementation address: 0xac4b40fF153260Fa80106f8c7F49b20aF459326A
Predicted Proxy address: 0x819F0Ed7ed246d65eeB5c54D79098B763A6593Bc
```

### 3. 部署到第一条链

```bash
forge script script/DeployTransferWalletCreate2.s.sol \
  --rpc-url $TEST_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

记录输出的地址！

### 4. 部署到第二条链

```bash
forge script script/DeployTransferWalletCreate2.s.sol \
  --rpc-url $TEST_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```


**地址会完全相同！** 🎉

## 🔍 验证合约代码

如果自动验证失败，可以手动验证（通常是 Etherscan 索引延迟）：

### 步骤 1：等待 1-2 分钟

等待 Etherscan 索引新部署的合约。

### 步骤 2：验证实现合约

```bash
forge verify-contract \
  <IMPLEMENTATION_ADDRESS> \
  src/transferWallet.sol:TransferWallet \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --rpc-url $TEST_RPC_URL
```

### 步骤 3：验证代理合约

```bash
# 先获取初始化数据
cast calldata "initialize(address)" <OWNER_ADDRESS>
# 输出例如：0xc4d66de80000000000000000000000008ff5a9ada6e69041aef6396381ede9b4c1ebf0b7

# 然后验证代理
forge verify-contract \
  <PROXY_ADDRESS> \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <IMPLEMENTATION_ADDRESS> <INIT_DATA>) \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --rpc-url $TEST_RPC_URL
```

### 实际示例（替换成你的地址）

```bash
# 验证实现合约
forge verify-contract \
  0xac4b40fF153260Fa80106f8c7F49b20aF459326A \
  src/transferWallet.sol:TransferWallet \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY

# 验证代理合约
forge verify-contract \
  0x819F0Ed7ed246d65eeB5c54D79098B763A6593Bc \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" 0xac4b40fF153260Fa80106f8c7F49b20aF459326A 0xc4d66de80000000000000000000000008ff5a9ada6e69041aef6396381ede9b4c1ebf0b7) \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 快速检查部署状态

```bash
# 检查实现合约是否有代码
cast code <IMPLEMENTATION_ADDRESS> --rpc-url $TEST_RPC_URL

# 检查代理合约是否有代码
cast code <PROXY_ADDRESS> --rpc-url $TEST_RPC_URL

# 如果返回 "0x" 说明没有代码（部署失败）
# 如果返回一长串十六进制，说明部署成功
```

## 📋 输出示例

```
=== Deployment Successful ===
Implementation address: 0xac4b40fF153260Fa80106f8c7F49b20aF459326A
Proxy address (Use this address): 0x819F0Ed7ed246d65eeB5c54D79098B763A6593Bc
Owner address: 0x8FF5a9ada6e69041AeF6396381eDE9B4C1ebf0b7

=== Multi-chain Deployment Info ===
These addresses will be IDENTICAL on all chains if you:
1. Use the same deployer address
2. Use the same salt values
3. Use the same Solidity compiler version
4. Use the same initialization parameters
```

## ⚠️ 重要提醒

### 必须相同的条件：

- ✅ 相同的私钥（部署账户）
- ✅ 相同的 salt 字符串（不要改脚本）
- ✅ 相同的合约代码（不要修改）
- ✅ 相同的编译器版本

### 字符串注意事项：

```solidity
// ❌ 这些会生成不同的地址！
"Test"  ≠  "test"      // 大小写敏感
"test"  ≠  "test "     // 空格也会影响
"测试"  ≠  "test"      // 不同字符
```

## 🌍 支持的链

理论上支持所有 EVM 兼容链：
- Ethereum (Mainnet, Sepolia)
- BSC (Mainnet, Testnet)
- Polygon (Mainnet, Mumbai)
- Arbitrum
- Optimism
- Avalanche
- Base
- 等等...

## 📚 更多文档

- **SALT_EXAMPLES.md** - Salt 字符串使用示例和最佳实践

## 🎯 核心功能

- ✅ 使用字符串 salt（易于修改）
- ✅ 自动预测地址
- ✅ 验证地址匹配
- ✅ 验证 owner 设置
- ✅ 多链地址一致

## 问题排查

### 地址不一致？

检查：
1. 私钥是否相同？
2. Salt 字符串是否完全一致？（包括大小写）
3. 合约代码是否有修改？
4. 编译器版本是否相同？

### 部署失败？

确保：
1. 账户有足够的 gas 费
2. RPC URL 正确
3. 私钥格式正确（不包含 0x）

## 快速命令

```bash
# 查看预期地址
forge script script/DeployTransferWalletCreate2.s.sol

# 正式部署（带验证）
forge script script/DeployTransferWalletCreate2.s.sol \
  --rpc-url $TEST_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

就是这么简单！🚀
