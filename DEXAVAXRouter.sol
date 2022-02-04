// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './IERC20.sol';
import './IDEXAVAXRouter.sol';
import './IDEXRouter.sol';

contract DEXAVAXRouter is IDEXRouter {
  IDEXAVAXRouter private router;

  constructor(address _router) {
    router = IDEXAVAXRouter(_router);
  }

  function getRouter() external view returns (address) {
    return address(router);
  }

  function factory() external view override returns (address) {
    return router.factory();
  }

  function WETH() external view override returns (address) {
    return router.WAVAX();
  }

  function addLiquidityETH(
    address token,
    uint256 amountTokenDesired,
    uint256 amountTokenMin,
    uint256 amountAVAXMin,
    address to,
    uint256 deadline
  )
    external
    payable
    override
    returns (
      uint256 amountToken,
      uint256 amountAVAX,
      uint256 liquidity
    )
  {
    IERC20 t = IERC20(token);
    t.transferFrom(msg.sender, address(this), amountToken);
    t.approve(address(router), amountToken);
    return
      router.addLiquidityAVAX{ value: msg.value }(
        token,
        amountTokenDesired,
        amountTokenMin,
        amountAVAXMin,
        to,
        deadline
      );
  }

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override {
    IERC20 t = IERC20(path[0]);
    t.transferFrom(msg.sender, address(this), amountIn);
    t.approve(address(router), amountIn);
    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amountIn,
      amountOutMin,
      path,
      to,
      deadline
    );
  }

  function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable override {
    router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{
      value: msg.value
    }(amountOutMin, path, to, deadline);
  }

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override {
    IERC20 t = IERC20(path[0]);
    t.transferFrom(msg.sender, address(this), amountIn);
    t.approve(address(router), amountIn);
    router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
      amountIn,
      amountOutMin,
      path,
      to,
      deadline
    );
  }
}
