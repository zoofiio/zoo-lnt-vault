// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Constants.sol";

library TokensTransfer {
  using SafeERC20 for IERC20;

  /// @dev Transfers a given amount of token.
  function transferTokens(
    address token,
    address from,
    address to,
    uint256 amount
  ) internal {
    if (token == Constants.NATIVE_TOKEN) {
      safeTransferNativeToken(from, to, amount);
    }
    else {
      safeTransferERC20(token, from, to, amount);
    }
  }

  /// @dev Transfers `amount` of native token to `to`.
  function safeTransferNativeToken(address from, address to, uint256 amount) internal {
    require(from != to, "Same address");
    require(from != address(0) && to != address(0), "Zero address");
    require(from == address(this) || to == address(this), "One of the addresses must be this contract");
    require(amount > 0, "Amount must be greater than 0");

    if (to == address(this)) {
      require(msg.value == amount, "Incorrect msg.value");
      return;
    }

    // solhint-disable avoid-low-level-calls
    // slither-disable-next-line low-level-calls
    (bool success, ) = to.call{ value: amount }("");
    require(success, "Native token transfer failed");
  }

  /// @dev Transfer `amount` of ERC20 token from `from` to `to`.
  function safeTransferERC20(
    address token,
    address from,
    address to,
    uint256 amount
  ) internal {
    require(from != to, "Same address");
    require(from != address(0) && to != address(0), "Zero address");
    require(from == address(this) || to == address(this), "One of the addresses must be this contract");
    require(amount > 0, "Amount must be greater than 0");

    if (from == address(this)) {
      IERC20(token).safeTransfer(to, amount);
    }
    else {
      IERC20(token).safeTransferFrom(from, to, amount);
    }
  }
}