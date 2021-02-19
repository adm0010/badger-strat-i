// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "AAVE-interfaces/ILendingPool.sol";

import "interfaces/sushi/ISushiChef.sol";
import "interfaces/sushi/IxSushi.sol";

import "interfaces/badger/IController.sol";
import "interfaces/badger/IMintr.sol";
import "interfaces/badger/IStrategy.sol";

import "../BaseStrategySwapper.sol";


/* Strategy
    A "meta-vault" strategy.
    Swap wETH for USDT, staked in CurveDAO 
*/

contract StrategyII is BaseStrategy {
	using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    address public p 

    event PickleHarvest(
        uint256 pickleFromStakingRewards,
        uint256 pickleFromHarvest,
        uint256 totalPickleToConvert,
        uint256 pickleRecycled,
        uint256 ethConverted,
        uint256 wethHarvested,
        uint256 lpComponentDeposited,
        uint256 lpDeposited,
        uint256 governancePerformanceFee,
        uint256 strategistPerformanceFee,
        uint256 timestamp,
        uint256 blockNumber
    );

    struct HarvestData {
        uint256 preExistingWant;
        uint256 preExistingPickle;
        uint256 pickleFromStakingRewards;
        uint256 pickleFromHarvest;
        uint256 totalPickleToConvert;
        uint256 pickleRecycled;
        uint256 ethConverted;
        uint256 wethHarvested;
        uint256 lpComponentDeposited;
        uint256 lpDeposited;
        uint256 lpPositionIncrease;
        uint256 governancePerformanceFee;
        uint256 strategistPerformanceFee;
    }

    struct TendData {
        uint256 pickleTended;
        uint256 wethConverted;
    }

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[4] memory _wantConfig,
        uint256 _pid,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(_governance, _strategist, _controller, _keeper, _guardian);

        want = _wantConfig[0];
        pickleJar = _wantConfig[1];
        curveSwap = _wantConfig[2];
        lpComponent = _wantConfig[3];

        pid = _pid;

        (address lp, , , ) = IPickleChef(pickleChef).poolInfo(pid);

        // // Confirm pickle-related addresses
        require(IPickleJar(pickleJar).token() == address(want), "PickleJar & Want mismatch");
        require(lp == pickleJar, "pid & Pickle jar mismatch");

        picklePerformanceFeeGovernance = _feeConfig[0];
        picklePerformanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        // Grant infinite approval to Pickle
        IERC20Upgradeable(want).safeApprove(pickleJar, type(uint256).max);
        IERC20Upgradeable(pickleJar).safeApprove(pickleChef, type(uint256).max);
        IERC20Upgradeable(pickle).safeApprove(pickleStaking, type(uint256).max);
    }

    /// ===== View Functions =====

    function getName() external override pure returns (string memory) {
        return "StrategyII";
    }

    // TODO: Return a valid balance of pool
    function balanceOfPool() public override view returns (uint256) {
        (uint256 _staked, ) = IPickleChef(pickleChef).userInfo(pid, address(this));
        return _staked;
    }

    function isTendable() public override view returns (bool) {
        return true;
    }

    function getProtectedTokens() external override view returns (address[] memory) {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = pickleJar;
        protectedTokens[2] = pickle;
        return protectedTokens;
    }

    /// ===== Permissioned Actions: Governance =====

    function setPicklePerformanceFeeStrategist(uint256 _picklePerformanceFeeStrategist) external {
        _onlyGovernance();
        picklePerformanceFeeStrategist = _picklePerformanceFeeStrategist;
    }

    function setPicklePerformanceFeeGovernance(uint256 _picklePerformanceFeeGovernance) external {
        _onlyGovernance();
        picklePerformanceFeeGovernance = _picklePerformanceFeeGovernance;
    }

    /// @notice Specify tokens used in yield process, should not be available to withdraw via withdrawOther()
    function _onlyNotProtectedTokens(address _asset) internal virtual;

 /// @notice Deposit any want in the strategy into the mechanics
    /// @dev want -> pickleJar, pWant -> pWantFarm (handled in postDeposit hook)
    function _deposit(uint256 _want) internal override {
        if (_want > 0) {
            IPickleJar(pickleJar).deposit(_want);
        }
    }

    function _postDeposit() internal override {
        uint256 _jar = IERC20Upgradeable(pickleJar).balanceOf(address(this));
        if (_jar > 0) {
            IPickleChef(pickleChef).deposit(pid, _jar);
        }
    }
}
