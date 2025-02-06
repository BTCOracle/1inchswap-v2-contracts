// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IChi.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/IOneInchCaller.sol";
import "./helpers/RevertReasonParser.sol";
import "./helpers/UniERC20.sol";


contract OneInchExchange is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;

    uint256 private constant _PARTIAL_FILL = 0x01;
    uint256 private constant _REQUIRES_EXTRA_ETH = 0x02;
    uint256 private constant _SHOULD_CLAIM = 0x04;
    uint256 private constant _BURN_FROM_MSG_SENDER = 0x08;
    uint256 private constant _BURN_FROM_TX_ORIGIN = 0x10;

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 guaranteedAmount;
        uint256 flags;
        address referrer;
        bytes permit;
    }

    event Swapped(
        address indexed sender,
        IERC20 indexed srcToken,
        IERC20 indexed dstToken,
        address dstReceiver,
        uint256 amount,
        uint256 spentAmount,
        uint256 returnAmount,
        uint256 minReturnAmount,
        uint256 guaranteedAmount,
        address referrer
    );

    event Error(
        string reason
    );

    function discountedSwap(
        IOneInchCaller caller,
        SwapDescription calldata desc,
        IOneInchCaller.CallDescription[] calldata calls
    )
        external
        payable
        returns (uint256 returnAmount)
    {
        uint256 initialGas = gasleft();

        address chiSource = address(0);
        if (desc.flags & _BURN_FROM_MSG_SENDER != 0) {
            chiSource = msg.sender;
        } else if (desc.flags & _BURN_FROM_TX_ORIGIN != 0) {
            chiSource = tx.origin; // solhint-disable-line avoid-tx-origin
        } else {
            revert("Incorrect CHI burn flags");
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = address(this).delegatecall(abi.encodeWithSelector(this.swap.selector, caller, desc, calls));
        if (success) {
            returnAmount = abi.decode(data, (uint256));
        } else {
            if (msg.value > 0) {
                msg.sender.transfer(msg.value);
