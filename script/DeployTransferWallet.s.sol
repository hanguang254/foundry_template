// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TransferWallet} from "../src/transferWallet.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTransferWallet is Script {
    function run() external {
        // 从环境变量获取私钥并计算部署者地址（将作为合约的 owner）
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer/Owner address:", deployer);
        
        // vm.startBroadcast() 会自动从以下来源获取私钥（按优先级）：
        // 1. --private-key 命令行参数
        // 2. PRIVATE_KEY 环境变量
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. 部署实现合约
        console.log("Deploying implementation contract...");
        TransferWallet implementation = new TransferWallet();
        console.log("Implementation address:", address(implementation));
        
        // 2. 编码初始化数据（使用部署者地址作为 owner）
        bytes memory initData = abi.encodeWithSelector(
            TransferWallet.initialize.selector,
            deployer
        );
        
        // 3. 部署代理合约
        console.log("Deploying proxy contract...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy address:", address(proxy));
        
        // 4. 验证部署
        TransferWallet proxyContract = TransferWallet(payable(address(proxy)));
        address owner = proxyContract.owner();
        console.log("Verification: Proxy contract Owner:", owner);
        require(owner == deployer, "Owner setup failed");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Successful ===");
        console.log("Implementation address:", address(implementation));
        console.log("Proxy address (Use this address):", address(proxy));
        console.log("Owner address:", owner);
    }
}
