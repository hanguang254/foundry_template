# TransferWallet 部署指南

这是一个可升级的代理合约部署指南。

## 前置准备

### 1. 设置环境变量

创建 `.env` 文件（参考 `.env.example`）：

```bash
# 部署者私钥（不要包含 0x 前缀）
PRIVATE_KEY=your_private_key_here

# 初始所有者地址（可选，如果不设置则使用部署者地址）
# INITIAL_OWNER=0x...

# RPC URL（根据要部署的网络选择）
RPC_URL=https://eth.llamarpc.com
```

### 2. 确保账户有足够的 ETH

部署需要支付 gas 费用，确保部署账户有足够的 ETH。

## 部署步骤

### 方式一：使用 forge script（推荐）

#### 1. 模拟部署（不实际发送交易）

```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

#### 2. 实际部署到链上

```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

#### 2.1. 如果遇到 Gas Limit 不足的问题

如果部署时遇到 gas limit 不足的错误，可以通过以下方式提高 gas limit：

**方式一：使用命令行参数（推荐）**
```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --gas-limit 10000000 \
  --gas-price 2000000000
```

**方式二：在 foundry.toml 中配置**
已在 `foundry.toml` 中配置了默认的 gas limit 和 gas price，如果需要调整，可以修改：
```toml
gas_limit = 10000000  # 根据实际需要调整
gas_price = 2000000000  # 根据网络情况调整
```

**方式三：使用更高的 gas limit**
```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --gas-limit 15000000 \
  --gas-price 2000000000
```

#### 3. 部署到特定网络

**Sepolia 测试网：**
```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY
```

**主网：**
```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url https://eth.llamarpc.com \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY
```

### 方式二：使用 cast 手动部署

如果需要更细粒度的控制，可以分步部署：

```bash
# 1. 部署实现合约
forge create src/transferWallet.sol:TransferWallet \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 2. 编码初始化数据
cast calldata "initialize(address)" YOUR_OWNER_ADDRESS

# 3. 部署代理合约（使用上一步得到的实现合约地址和初始化数据）
forge create lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args IMPLEMENTATION_ADDRESS INIT_DATA \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## 部署后的验证

部署成功后，你会得到两个地址：
1. **Implementation 地址**：实现合约地址（用于未来升级）
2. **Proxy 地址**：代理合约地址（这是你实际使用的合约地址）

### 1. 检查合约状态

```bash
# 检查 owner
cast call PROXY_ADDRESS "owner()" --rpc-url $RPC_URL

# 检查是否已初始化
cast call PROXY_ADDRESS "owner()" --rpc-url $RPC_URL
```

### 2. 在 Etherscan 上验证合约代码

#### 方式一：使用 forge verify-contract（推荐）

**验证实现合约：**
```bash
forge verify-contract \
  0x07FFcCE37D34606c22acdc4DBD20d3c10cc05Ba5 \
  src/transferWallet.sol:TransferWallet \
  --chain-id 11155111 \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY \
  --rpc-url $RPC_URL
```

**验证代理合约：**
首先获取初始化数据：
```bash
# 获取初始化数据（假设 owner 是部署者地址）
cast calldata "initialize(address)" 0x8FF5a9ada6e69041AeF6396381eDE9B4C1ebf0b7
```

然后验证代理合约：
```bash
forge verify-contract \
  0x0Fc98C901750F2a5b81D128eb9c1234C60F5Db47 \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" 0x07FFcCE37D34606c22acdc4DBD20d3c10cc05Ba5 0xc4d66de80000000000000000000000008ff5a9ada6e69041aef6396381ede9b4c1ebf0b7) \
  --chain-id 11155111 \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY \
  --rpc-url $RPC_URL
```

#### 方式二：部署时自动验证

在部署命令中添加 `--verify` 参数：
```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY
```

**获取 Etherscan API Key：**
1. 访问 https://etherscan.io/apis
2. 注册账号并创建 API Key
3. 将 API Key 添加到 `.env` 文件：
   ```bash
   ETHERSCAN_API_KEY=your_api_key_here
   ```

## 升级合约

未来如果需要升级合约：

```bash
# 1. 部署新的实现合约
forge create src/transferWallet.sol:TransferWallet \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 2. 调用升级函数（通过代理）
cast send PROXY_ADDRESS \
  "upgradeToAndCall(address,bytes)" \
  NEW_IMPLEMENTATION_ADDRESS \
  "" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## proxy指向升级合约

```bash
cast send proxy地址 \
  "upgradeTo(address)" 升级合约地址 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

验证升级合约
forge verify-contract 升级合约地址 \
  src/文件名称.sol:合约名称 \
  --chain-id chain_id \
  --etherscan-api-key apikey

```
## 注意事项

1. **私钥安全**：永远不要将私钥提交到 Git 仓库
2. **代理地址**：使用代理地址与合约交互，不要使用实现合约地址
3. **初始化**：确保只初始化一次，否则会失败
4. **Owner 权限**：妥善保管 owner 私钥，只有 owner 可以升级合约
5. **Gas 费用**：部署可升级合约需要更多 gas，确保账户余额充足

## 常见问题

### Q: 如何查看部署的合约？
A: 使用 Etherscan 或区块浏览器查看代理地址。

### Q: 如何验证合约代码？
A: 使用 `forge verify-contract` 命令验证合约。对于可升级代理合约，需要验证两个合约：

**1. 验证实现合约（Implementation）：**
```bash
forge verify-contract \
  IMPLEMENTATION_ADDRESS \
  src/transferWallet.sol:TransferWallet \
  --chain-id 11155111 \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY \
  --rpc-url $RPC_URL
```

**2. 验证代理合约（Proxy）：**
```bash
forge verify-contract \
  PROXY_ADDRESS \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" IMPLEMENTATION_ADDRESS INIT_DATA) \
  --chain-id 11155111 \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY \
  --rpc-url $RPC_URL
```

**注意：**
- 将 `IMPLEMENTATION_ADDRESS` 和 `PROXY_ADDRESS` 替换为实际部署的地址
- 将 `YOUR_ETHERSCAN_API_KEY` 替换为你的 Etherscan API Key
- `INIT_DATA` 是初始化数据的编码（可以通过 `cast calldata "initialize(address)" OWNER_ADDRESS` 获取）
- `--chain-id` 根据网络选择：Sepolia (11155111)、主网 (1) 等

**或者使用部署时的 `--verify` 参数自动验证：**
```bash
forge script script/DeployTransferWallet.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key YOUR_ETHERSCAN_API_KEY
```

### Q: 部署失败怎么办？
A: 检查：
- 账户余额是否足够
- RPC URL 是否正确
- 私钥是否正确
- 网络是否支持
- **Gas Limit 是否足够**：如果遇到 "out of gas" 错误，尝试增加 `--gas-limit` 参数（如 `--gas-limit 15000000`）

### Q: 如何提高 Gas Limit？
A: 有三种方式：
1. **命令行参数**：在部署命令中添加 `--gas-limit 10000000`（推荐）
2. **配置文件**：在 `foundry.toml` 中设置 `gas_limit = 10000000`
3. **环境变量**：某些网络可能需要更高的 gas limit，根据实际情况调整
