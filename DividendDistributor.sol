// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './interfaces/IBEP20.sol';
import './interfaces/IDEXRouter.sol';
import './interfaces/IDividendDistributor.sol';

contract DividendDistributor is IDividendDistributor {
  using SafeMath for uint256;

  address _token;

  struct Share {
    uint256 amount;
    uint256 totalExcluded; // excluded dividend
    uint256 totalRealised;
  }

  IBEP20 EP;
  address WAVAX;
  IDEXRouter router;

  address[] shareholders;
  mapping(address => uint256) shareholderIndexes;
  mapping(address => uint256) shareholderClaims;

  mapping(address => Share) public shares;

  uint256 public totalShares;
  uint256 public totalDividends;
  uint256 public totalDistributed; // to be shown in UI
  uint256 public dividendsPerShare;
  uint256 public dividendsPerShareAccuracyFactor = 10**36;

  uint256 public minPeriod = 1 hours;
  uint256 public minDistribution = 10 * (10**18);

  uint256 currentIndex;

  bool initialized;
  modifier initialization() {
    require(!initialized);
    _;
    initialized = true;
  }

  modifier onlyToken() {
    require(msg.sender == _token);
    _;
  }

  constructor(
    address _router,
    address _WETH,
    address _printerToken
  ) {
    router = IDEXRouter(_router);
    _token = msg.sender;
    WAVAX = _WETH;
    EP = IBEP20(_printerToken);
  }

  function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution)
    external
    override
    onlyToken
  {
    minPeriod = _minPeriod;
    minDistribution = _minDistribution;
  }

  function setShare(address shareholder, uint256 amount)
    external
    override
    onlyToken
  {
    if (shares[shareholder].amount > 0) {
      distributeDividend(shareholder, false);
    }

    if (amount > 0 && shares[shareholder].amount == 0) {
      addShareholder(shareholder);
    } else if (amount == 0 && shares[shareholder].amount > 0) {
      removeShareholder(shareholder);
    }

    totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
    shares[shareholder].amount = amount;
    shares[shareholder].totalExcluded = getCumulativeDividends(
      shares[shareholder].amount
    );
  }

  function deposit() external payable override onlyToken {
    uint256 balanceBefore = EP.balanceOf(address(this));

    address[] memory path = new address[](2);
    path[0] = WAVAX;
    path[1] = address(EP);

    router.swapExactETHForTokensSupportingFeeOnTransferTokens{
      value: msg.value
    }(0, path, address(this), block.timestamp);

    uint256 amount = EP.balanceOf(address(this)).sub(balanceBefore);

    totalDividends = totalDividends.add(amount);
    dividendsPerShare = dividendsPerShare.add(
      dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)
    );
  }

  function process(uint256 gas) external override onlyToken {
    uint256 shareholderCount = shareholders.length;

    if (shareholderCount == 0) {
      return;
    }

    uint256 gasUsed = 0;
    uint256 gasLeft = gasleft();

    uint256 iterations = 0;

    while (gasUsed < gas && iterations < shareholderCount) {
      if (currentIndex >= shareholderCount) {
        currentIndex = 0;
      }

      if (shouldDistribute(shareholders[currentIndex])) {
        distributeDividend(shareholders[currentIndex], false);
      }

      gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
      gasLeft = gasleft();
      currentIndex++;
      iterations++;
    }
  }

  function shouldDistribute(address shareholder) internal view returns (bool) {
    return
      shareholderClaims[shareholder] + minPeriod < block.timestamp &&
      getUnpaidEarnings(shareholder) > minDistribution;
  }

  function distributeDividend(address shareholder, bool compound) internal {
    if (shares[shareholder].amount == 0) {
      return;
    }

    uint256 amount = getUnpaidEarnings(shareholder);
    if (amount > 0) {
      totalDistributed = totalDistributed.add(amount);
      if (compound && address(EP) != _token) {
        EP.approve(address(router), amount);
        address[] memory path = new address[](3);
        path[0] = address(EP);
        path[1] = WAVAX;
        path[2] = _token;
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          amount,
          0, // TODO: calculate estimate, and add here accounting for slippage (~25%+)
          path,
          shareholder,
          block.timestamp
        );
      } else {
        EP.transfer(shareholder, amount);
      }
      shareholderClaims[shareholder] = block.timestamp;
      shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(
        amount
      );
      shares[shareholder].totalExcluded = getCumulativeDividends(
        shares[shareholder].amount
      );
    }
  }

  function claimDividend(bool compound) external {
    distributeDividend(msg.sender, compound);
  }

  /*
returns the  unpaid earnings
*/
  function getUnpaidEarnings(address shareholder)
    public
    view
    returns (uint256)
  {
    if (shares[shareholder].amount == 0) {
      return 0;
    }

    uint256 shareholderTotalDividends = getCumulativeDividends(
      shares[shareholder].amount
    );
    uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

    if (shareholderTotalDividends <= shareholderTotalExcluded) {
      return 0;
    }

    return shareholderTotalDividends.sub(shareholderTotalExcluded);
  }

  function getCumulativeDividends(uint256 share)
    internal
    view
    returns (uint256)
  {
    return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
  }

  function addShareholder(address shareholder) internal {
    shareholderIndexes[shareholder] = shareholders.length;
    shareholders.push(shareholder);
  }

  function removeShareholder(address shareholder) internal {
    shareholders[shareholderIndexes[shareholder]] = shareholders[
      shareholders.length - 1
    ];
    shareholderIndexes[
      shareholders[shareholders.length - 1]
    ] = shareholderIndexes[shareholder];
    shareholders.pop();
  }
}
