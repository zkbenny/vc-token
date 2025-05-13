// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TokenReleaseDelayModule = buildModule("TokenReleaseDelayModule", (m) => {
  const zklToken = m.getParameter("zklToken");

  const impl = m.contract("TokenReleaseDelay", [zklToken]);
  const initData = m.encodeFunctionCall(impl,"initialize", []);
  const proxy = m.contract("ERC1967Proxy", [
    impl,
    initData,
  ]);

  return { proxy, impl };
});

export default TokenReleaseDelayModule;
