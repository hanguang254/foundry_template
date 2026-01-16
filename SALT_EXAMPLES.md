# Salt 字符串使用示例

## 如何自定义 Salt 值

在 `script/DeployTransferWalletCreate2.s.sol` 中，你可以轻松修改 salt 字符串：

### 当前设置（示例）

```solidity
string constant IMPLEMENTATION_SALT_STRING = "test_shahai_implementation";
string constant PROXY_SALT_STRING = "test_shahai_proxy";
```

## 推荐的命名方式

### 方式一：项目名称 + 版本

```solidity
string constant IMPLEMENTATION_SALT_STRING = "MyDApp_v1_implementation";
string constant PROXY_SALT_STRING = "MyDApp_v1_proxy";
```

适用于：有明确版本管理的项目

### 方式二：项目名称 + 网络类型

```solidity
string constant IMPLEMENTATION_SALT_STRING = "MyProject_mainnet_impl";
string constant PROXY_SALT_STRING = "MyProject_mainnet_proxy";
```

适用于：区分测试网和主网部署

### 方式三：日期 + 项目名称

```solidity
string constant IMPLEMENTATION_SALT_STRING = "2024_MyProject_implementation";
string constant PROXY_SALT_STRING = "2024_MyProject_proxy";
```

适用于：长期维护的项目

### 方式四：简单易记的标识

```solidity
string constant IMPLEMENTATION_SALT_STRING = "shahai_wallet_impl";
string constant PROXY_SALT_STRING = "shahai_wallet_proxy";
```

适用于：个人项目或小型项目

## 实际使用示例

### 示例 1：多链 DeFi 项目

```solidity
// 部署到多条链的 DeFi 协议
string constant IMPLEMENTATION_SALT_STRING = "DefiProtocol_2024_impl";
string constant PROXY_SALT_STRING = "DefiProtocol_2024_proxy";
```

这样在 Ethereum、BSC、Polygon 等多条链上都会获得相同的地址。

### 示例 2：NFT 市场

```solidity
// NFT 交易市场
string constant IMPLEMENTATION_SALT_STRING = "NFTMarket_v2_implementation";
string constant PROXY_SALT_STRING = "NFTMarket_v2_proxy";
```

### 示例 3：测试环境

```solidity
// 测试网部署
string constant IMPLEMENTATION_SALT_STRING = "test_shahai_2024_impl";
string constant PROXY_SALT_STRING = "test_shahai_2024_proxy";
```

## 修改 Salt 的步骤

### 1. 编辑脚本

打开 `script/DeployTransferWalletCreate2.s.sol`：

```solidity
contract DeployTransferWalletCreate2 is Script {
    // 在这里修改你的 salt 字符串
    string constant IMPLEMENTATION_SALT_STRING = "your_project_name_impl";
    string constant PROXY_SALT_STRING = "your_project_name_proxy";
    
    // 其他代码保持不变...
}
```

### 2. 测试计算地址

运行脚本查看将会生成的地址：

```bash
forge script script/DeployTransferWalletCreate2.s.sol
```

输出会显示：
```
Implementation Salt String: your_project_name_impl
Implementation Salt: 0xabcd1234...
Predicted Implementation address: 0x742d35Cc...
Proxy Salt String: your_project_name_proxy
Proxy Salt: 0x5678efab...
Predicted Proxy address: 0x2e234DAe...
```

### 3. 记录地址

在部署前记录预测的地址，以便在所有链上验证。

### 4. 部署到多条链

使用相同的 salt 字符串部署到不同的链。

## 重要提醒

### ✅ 务必保证

1. **所有链使用相同的 salt 字符串**
   ```solidity
   // 链 A 和 链 B 必须完全相同
   string constant IMPLEMENTATION_SALT_STRING = "MyProject_impl";
   ```

2. **字符串大小写敏感**
   ```solidity
   // ❌ 这些会生成不同的地址！
   "MyProject_impl"  // 与
   "myproject_impl"  // 不同！
   ```

3. **包括空格和特殊字符都会影响**
   ```solidity
   // ❌ 这些会生成不同的地址！
   "MyProject_impl"   // 与
   "MyProject _impl"  // 不同（注意空格）
   ```

### ❌ 避免

1. **不要在不同链上使用不同的 salt**
   ```solidity
   // ❌ 错误示例
   // 在 Ethereum 上：
   string constant PROXY_SALT_STRING = "ethereum_proxy";
   
   // 在 BSC 上：
   string constant PROXY_SALT_STRING = "bsc_proxy";
   // 这样会导致地址不同！
   ```

2. **不要包含动态值**
   ```solidity
   // ❌ 错误示例（时间戳会变化）
   string constant SALT_STRING = "MyProject_2024_01_16";
   ```

## Salt 转换原理

脚本内部使用以下函数将字符串转换为 bytes32：

```solidity
function getSalt(string memory saltString) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(saltString));
}
```

例如：
- 输入：`"test_shahai_implementation"`
- 输出：`0x7f9fade1c0d57a7af66ab4ead79fade1c0d57a7af66ab4ead7c2c95bcce29f69`（示例）

这个转换是确定性的，相同的字符串永远生成相同的 bytes32 值。

## 常见问题

### Q: 可以使用中文吗？

A: 可以，但不推荐。中文可能在不同系统或编辑器中有编码问题。

```solidity
// ✅ 推荐：使用英文和数字
string constant SALT_STRING = "shahai_project_v1";

// ⚠️ 不推荐：使用中文
string constant SALT_STRING = "沙海项目_v1";
```

### Q: 如何生成更安全的 salt？

A: 使用有意义但难以猜测的组合：

```solidity
// 项目名 + 随机字符串 + 用途
string constant SALT_STRING = "MyProject_8x9k2m_implementation";
```

### Q: 能否使用环境变量？

A: CREATE2 需要在编译时确定 salt，所以必须硬编码在脚本中。但你可以为不同环境创建不同的脚本文件。

## 快速参考

修改这两行即可：

```solidity
string constant IMPLEMENTATION_SALT_STRING = "改成你的项目名_impl";
string constant PROXY_SALT_STRING = "改成你的项目名_proxy";
```

就这么简单！
