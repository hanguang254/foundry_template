// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
// import {TransferWallet} from "../src/transferWallet.sol";
import {TransferWalletV2} from "../src/TransferWalletV2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployTransferWalletCreate2
 * @notice 使用 CREATE2 部署 TransferWallet，确保多链地址一致
 * @dev 通过固定 salt 值，在不同链上部署相同地址的合约
 */
contract DeployTransferWalletCreate2 is Script {
    // 可以轻松修改的 salt 字符串 - 修改这些字符串会生成不同的地址
    // 示例：使用 "test_shahai" 作为 salt 种子
    string constant IMPLEMENTATION_SALT_STRING = "0xshahai_meme_wallet_v2";
    string constant PROXY_SALT_STRING = "0xshahai_meme_wallet_v2";
    
    /**
     * @dev 从字符串生成 salt
     * @param saltString 字符串形式的 salt
     */
    function getSalt(string memory saltString) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(saltString));
    }
    
    function run() external {
        // 从环境变量获取私钥并计算部署者地址（将作为合约的 owner）
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // 生成 salt
        bytes32 implementationSalt = getSalt(IMPLEMENTATION_SALT_STRING);
        bytes32 proxySalt = getSalt(PROXY_SALT_STRING);
        
        console.log("Deployer/Owner address:", deployer);
        console.log("\n=== Using CREATE2 for deterministic deployment ===");
        console.log("Implementation Salt String:", IMPLEMENTATION_SALT_STRING);
        console.log("Implementation Salt:", vm.toString(implementationSalt));
        console.log("Proxy Salt String:", PROXY_SALT_STRING);
        console.log("Proxy Salt:", vm.toString(proxySalt));
        
        // 使用 Foundry 的 vm.computeCreate2Address 计算预期地址
        // 注意：Foundry 的 CREATE2 使用默认的 Create2Deployer
        address predictedImplementation = vm.computeCreate2Address(
            implementationSalt,
            hashInitCode(type(TransferWalletV2).creationCode)
        );
        console.log("\nPredicted Implementation address:", predictedImplementation);
        
        // 编码初始化数据
        bytes memory initData = abi.encodeWithSelector(
            TransferWalletV2.initialize.selector,
            deployer
        );
        
        // 计算代理合约的创建代码（包括构造函数参数）
        bytes memory proxyCreationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(predictedImplementation, initData)
        );
        
        address predictedProxy = vm.computeCreate2Address(
            proxySalt,
            hashInitCode(proxyCreationCode)
        );
        console.log("Predicted Proxy address:", predictedProxy);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. 使用 CREATE2 部署实现合约
        console.log("\n[1/2] Deploying implementation contract with CREATE2...");
        TransferWalletV2 implementation = new TransferWalletV2{salt: implementationSalt}();
        console.log("Implementation deployed at:", address(implementation));
        
        // 验证地址是否符合预期
        require(
            address(implementation) == predictedImplementation,
            "Implementation address mismatch!"
        );
        console.log("[OK] Implementation address verified");
        
        // 2. 使用 CREATE2 部署代理合约
        console.log("\n[2/2] Deploying proxy contract with CREATE2...");
        ERC1967Proxy proxy = new ERC1967Proxy{salt: proxySalt}(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));
        
        // 验证地址是否符合预期
        require(
            address(proxy) == predictedProxy,
            "Proxy address mismatch!"
        );
        console.log("[OK] Proxy address verified");
        
        // 3. 验证部署
        TransferWalletV2 proxyContract = TransferWalletV2(payable(address(proxy)));
        address owner = proxyContract.owner();
        console.log("\n[Verification] Proxy contract Owner:", owner);
        require(owner == deployer, "Owner setup failed");
        console.log("[OK] Owner verification passed");
        
        // 验证实现地址
        address actualImplementation = proxyContract.getImplementation();
        console.log("[Verification] Implementation from proxy:", actualImplementation);
        require(actualImplementation == address(implementation), "Implementation verification failed");
        console.log("[OK] Implementation verification passed");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Successful ===");
        console.log("Implementation address:", address(implementation));
        console.log("Proxy address (Use this address):", address(proxy));
        console.log("Owner address:", owner);
        console.log("\n=== Multi-chain Deployment Info ===");
        console.log("These addresses will be IDENTICAL on all chains if you:");
        console.log("1. Use the same deployer address");
        console.log("2. Use the same salt values");
        console.log("3. Use the same Solidity compiler version");
        console.log("4. Use the same initialization parameters");
        console.log("\nTo deploy on another chain, run:");
        console.log("forge script script/DeployTransferWalletCreate2.s.sol \\");
        console.log("  --rpc-url <CHAIN_RPC_URL> \\");
        console.log("  --broadcast \\");
        console.log("  --verify \\");
        console.log("  --etherscan-api-key <API_KEY>");
    }
}
