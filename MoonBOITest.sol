/**
Moonboi: $BOI
- 10% reflections paid in token chosen by vote

Tokenomics:
10% reflections paid in choice token
3% tax for treasury/operations
3% allocated to auto-liquidity

Website:
https://www.moonboi.io

Telegram:
https://t.me/moonboiDAO

Twitter:
https://twitter.com/MoonboiDAO
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './IDEXFactory.sol';
import './Auth.sol';
import './DividendDistributor.sol';
import './DEXAVAXRouter.sol';

/// @title The MoonBoi Variable Printer
/// @author SteelAndQuill and fatal1ty.eth
/// @notice This token routes 10% of transaction payments to existing holders in the form of BoiPrint, reserves 3% for protocol ops, and provides 3% as LP.
contract Moonboi is IERC20, Auth {
  using SafeMath for uint256;
  
  uint256 public constant MASK = type(uint128).max;
  
  // ********************************************************************************
  // ********************************************************************************
  // ENVIRONMENT-SPECIFIC VARIABLES

  // Most new DEX's out there are forks of Uniswap, and most implement
  // the exact interfaces or very similar to what it has in order to function.
  // For Trader Joe on AVAX, they use a similar API in their contracts except
  // they change the names of some functions. See ./DEXAVAXRouter.sol for more info,
  // but this boolean is used in order to use the appropriate interface/abstract
  // contract when setting up this contract to support any DEX.
  bool isAVAX = true;

  // DEX router
  // AVAX mainnet: 0xb5b2444eDF79b00d40f463f79158D1187a0D0c25 Official Thorus.fi router
  // Fuji testnet: 0xd62b35686CbdfF7fB067EAb403dE38702DB01fd8 SAQ-deployed clone of Thorus Router
  address constant ROUTER = 0xd62b35686CbdfF7fB067EAb403dE38702DB01fd8;

  // "printer" token
  // AVAX mainnet DAI.e: 0xd586e7f844cea2f87f50152665bcbc2c279d8d70
  // Fuji SAQ MOJO: 0x2b7A4a839aB21bBd8bf158F52980a1e09024E9D2
  address BoiPrint = 0x2b7A4a839aB21bBd8bf158F52980a1e09024E9D2; // BoiPrint

  // AVAX mainnet WAVAX: 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7
  // Fuji testnet WAVAX: 0xd00ae08403B9bbb9124bB305C09058E32C39A48c
  address public WAVAX = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
  // ********************************************************************************
  // ********************************************************************************

  address DEAD = 0x000000000000000000000000000000000000dEaD;
  address ZERO = 0x0000000000000000000000000000000000000000;

  string constant _name = 'Moonboi';
  string constant _symbol = 'BOI';
  uint8 constant _decimals = 18;

  uint256 _totalSupply = 1_000_000_000_000_000 * (10**_decimals);
  uint256 public _maxTxAmount = _totalSupply.div(40); // 2.5%
  uint256 public _maxWallet = _totalSupply.div(40); // 2.5%

  mapping(address => uint256) _balances;
  mapping(address => mapping(address => uint256)) _allowances;

  mapping(address => bool) isFeeExempt;
  mapping(address => bool) isTxLimitExempt;
  mapping(address => bool) isDividendExempt;
  mapping(address => bool) public _isFree;

  bool public transferEnabled = false;

  uint256 liquidityFee = 200; //change to adjustable
  uint256 buybackFee = 0;
  uint256 reflectionFee = 1200; //change to adjustable
  uint256 marketingFee = 500; //change to adjustable
  uint256 totalFee = 1900; //change to sum of numbers
  uint256 feeDenominator = 10000;

  address public autoLiquidityReceiver =
     0x3e7A3cdCFbaa89401dE226a3e72805510b65eD30; //change to multisig code will be broken here for now
  address public marketingFeeReceiver =
     0x3e7A3cdCFbaa89401dE226a3e72805510b65eD30; //change to multisig code will be broken here for now

  uint256 targetLiquidity = 10;
  uint256 targetLiquidityDenominator = 100;

  IDEXRouter public router;
  address public pair;

  uint256 public launchedAt;
  uint256 public launchedAtTimestamp;

  uint256 buybackMultiplierNumerator = 200;
  uint256 buybackMultiplierDenominator = 100;
  uint256 buybackMultiplierTriggeredAt;
  uint256 buybackMultiplierLength = 30 minutes;

  bool public autoBuybackEnabled = false;
  mapping(address => bool) buyBacker;
  uint256 autoBuybackCap;
  uint256 autoBuybackAccumulator;
  uint256 autoBuybackAmount;
  uint256 autoBuybackBlockPeriod;
  uint256 autoBuybackBlockLast;

  DividendDistributor distributor;
  address public distributorAddress;

  uint256 distributorGas = 500000;

  bool public swapEnabled = true;
  uint256 public swapPercentMax = 50; // % of amount being swapped
  uint256 public swapThresholdMax = _totalSupply / 5000; // 0.0025%
  bool inSwap;
  modifier swapping() {
    inSwap = true;
    _;
    inSwap = false;
  }
  
  constructor() Auth(msg.sender) {
    uint256 MAX = ~uint256(0);
    router = isAVAX ? new DEXAVAXRouter(ROUTER) : IDEXRouter(ROUTER);
    pair = IDEXFactory(router.factory()).createPair(WAVAX, address(this));
    _allowances[address(this)][ROUTER] = MAX;
    _allowances[address(this)][address(router)] = MAX;
    WAVAX = router.WETH();
    distributor = new DividendDistributor(address(router), WAVAX, BoiPrint);
    distributorAddress = address(distributor);

    isFeeExempt[msg.sender] = true;
    isTxLimitExempt[msg.sender] = true;
    isDividendExempt[pair] = true;
    isDividendExempt[address(this)] = true;
    isDividendExempt[DEAD] = true;
    buyBacker[msg.sender] = true;

    autoLiquidityReceiver = msg.sender;

    approve(ROUTER, MAX);
    approve(address(router), MAX);
    approve(address(pair), MAX);
    _balances[msg.sender] = _totalSupply;
    emit Transfer(address(0), msg.sender, _totalSupply);
  }
  
    receive() external payable {}

  function totalSupply() external view override returns (uint256) {
    return _totalSupply;
  }

  function decimals() external pure override returns (uint8) {
    return _decimals;
  }

  function symbol() external pure override returns (string memory) {
    return _symbol;
  }

  function name() external pure override returns (string memory) {
    return _name;
  }

  function getOwner() external view override returns (address) {
    return owner;
  }

  modifier onlyBuybacker() {
    require(buyBacker[msg.sender] == true, '');
    _;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account];
  }

  function allowance(address holder, address spender)
    external
    view
    override
    returns (uint256)
  {
    return _allowances[holder][spender];
  }

  function approve(address spender, uint256 amount)
    public
    override
    returns (bool)
  {
    _allowances[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function approveMax(address spender) external returns (bool) {
    return approve(spender, _totalSupply);
  }

  function transfer(address recipient, uint256 amount)
    external
    override
    returns (bool)
  {
    return _transferFrom(msg.sender, recipient, amount);
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external override returns (bool) {
    if (_allowances[sender][msg.sender] != _totalSupply) {
      _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(
        amount,
        'Insufficient Allowance'
      );
    }

    return _transferFrom(sender, recipient, amount);
  }

  function _transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) internal returns (bool) {
    require(
      transferEnabled || isAuthorized(msg.sender) || isAuthorized(sender),
      'Transfer is enabled or user is authorized'
    );

    if (inSwap) {
      return _basicTransfer(sender, recipient, amount);
    }

    // Max  tx check
    // bool isBuy = sender == pair || sender == ROUTER;
    bool isSell = recipient == pair || recipient == ROUTER;

    checkTxLimit(sender, amount);

    // Max wallet check excluding pair and router
    if (!isSell && !_isFree[recipient]) {
      require(
        (_balances[recipient] + amount) < _maxWallet,
        'Max wallet has been triggered'
      );
    }

    // No swapping on buy and tx
    if (isSell) {
      if (shouldSwapBack(amount)) {
        swapBack(amount);
      }
      if (shouldAutoBuyback()) {
        triggerAutoBuyback();
      }
    }
    // if(!launched() && recipient == pair){ require(_balances[sender] > 0); launch(); }

    _balances[sender] = _balances[sender].sub(amount, 'Insufficient Balance');

    uint256 amountReceived = shouldTakeFee(sender)
      ? takeFee(sender, recipient, amount)
      : amount;

    _balances[recipient] = _balances[recipient].add(amountReceived);

    if (!isDividendExempt[sender]) {
      try distributor.setShare(sender, _balances[sender]) {} catch {}
    }
    if (!isDividendExempt[recipient]) {
      try distributor.setShare(recipient, _balances[recipient]) {} catch {}
    }

    try distributor.process(distributorGas) {} catch {}

    emit Transfer(sender, recipient, amountReceived);
    return true;
  }

  function _basicTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal returns (bool) {
    _balances[sender] = _balances[sender].sub(amount, 'Insufficient Balance');
    _balances[recipient] = _balances[recipient].add(amount);
    //        emit Transfer(sender, recipient, amount);
    return true;
  }

  function checkTxLimit(address sender, uint256 amount) internal view {
    require(
      amount <= _maxTxAmount || isTxLimitExempt[sender],
      'TX Limit Exceeded'
    );
  }

  function shouldTakeFee(address sender) internal view returns (bool) {
    return !isFeeExempt[sender];
  }

  function takeFee(
    address sender,
    address receiver,
    uint256 amount
  ) internal returns (uint256) {
    uint256 feeAmount = amount.mul(totalFee).div(feeDenominator);

    _balances[address(this)] = _balances[address(this)].add(feeAmount);
    emit Transfer(sender, address(this), feeAmount);

    return amount.sub(feeAmount);
  }

  function getSwapAmount(uint256 _transferAmount)
    public
    view
    returns (uint256)
  {
    uint256 amountFromTxnPercMax = _transferAmount.mul(swapPercentMax).div(100);
    return
      amountFromTxnPercMax > swapThresholdMax
        ? swapThresholdMax
        : amountFromTxnPercMax;
  }

  function shouldSwapBack(uint256 _transferAmount)
    internal
    view
    returns (bool)
  {
    return
      msg.sender != pair &&
      !inSwap &&
      swapEnabled &&
      _balances[address(this)] >= getSwapAmount(_transferAmount);
  }

  function swapBack(uint256 _transferAmount) internal swapping {
    uint256 dynamicLiquidityFee = isOverLiquified(
      targetLiquidity,
      targetLiquidityDenominator
    )
      ? 0
      : liquidityFee;
    uint256 swapAmount = getSwapAmount(_transferAmount);
    uint256 amountToLiquify = swapAmount
      .mul(dynamicLiquidityFee)
      .div(totalFee)
      .div(2);
    uint256 amountToSwap = swapAmount.sub(amountToLiquify);

    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = WAVAX;
    uint256 balanceBefore = address(this).balance;

    _checkAndApproveTokensForRouter(amountToSwap);
    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      amountToSwap,
      0,
      path,
      address(this),
      block.timestamp
    );

    uint256 amountAVAX = address(this).balance.sub(balanceBefore);

    uint256 totalAVAXFee = totalFee.sub(dynamicLiquidityFee.div(2));

    uint256 amountAVAXLiquidity = amountAVAX
      .mul(dynamicLiquidityFee)
      .div(totalAVAXFee)
      .div(2);
    uint256 amountAVAXReflection = amountAVAX.mul(reflectionFee).div(
      totalAVAXFee
    );
    uint256 amountAVAXMarketing = amountAVAX.mul(marketingFee).div(
      totalAVAXFee
    );

    try distributor.deposit{ value: amountAVAXReflection }() {} catch {}
    payable(marketingFeeReceiver).call{ value: amountAVAXMarketing }('');

    if (amountToLiquify > 0) {
      _checkAndApproveTokensForRouter(amountToLiquify);
      router.addLiquidityETH{ value: amountAVAXLiquidity }(
        address(this),
        amountToLiquify,
        0,
        0,
        autoLiquidityReceiver,
        block.timestamp
      );
      emit AutoLiquify(amountAVAXLiquidity, amountToLiquify);
    }
  }

  function shouldAutoBuyback() internal view returns (bool) {
    return
      msg.sender != pair &&
      !inSwap &&
      autoBuybackEnabled &&
      autoBuybackBlockLast + autoBuybackBlockPeriod <= block.number && // After N blocks from last buyback
      address(this).balance >= autoBuybackAmount;
  }

  function triggerZeusBuyback(uint256 amount, bool triggerBuybackMultiplier)
    external
    authorized
  {
    buyTokens(amount, DEAD);
    if (triggerBuybackMultiplier) {
      buybackMultiplierTriggeredAt = block.timestamp;
      emit BuybackMultiplierActive(buybackMultiplierLength);
    }
  }

  function clearBuybackMultiplier() external authorized {
    buybackMultiplierTriggeredAt = 0;
  }

  function enableTransfer() external authorized {
    transferEnabled = true;
  }

  function triggerAutoBuyback() internal {
    buyTokens(autoBuybackAmount, DEAD);
    autoBuybackBlockLast = block.number;
    autoBuybackAccumulator = autoBuybackAccumulator.add(autoBuybackAmount);
    if (autoBuybackAccumulator > autoBuybackCap) {
      autoBuybackEnabled = false;
    }
  }

  function buyTokens(uint256 amount, address to) internal swapping {
    address[] memory path = new address[](2);
    path[0] = WAVAX;
    path[1] = address(this);

    router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: amount }(
      0,
      path,
      to,
      block.timestamp
    );
  }

  function Sweep() external authorized {
    uint256 balance = address(this).balance;
    payable(msg.sender).call{ value: balance }('');
  }

  function setAutoBuybackSettings(
    bool _enabled,
    uint256 _cap,
    uint256 _amount,
    uint256 _period
  ) external authorized {
    autoBuybackEnabled = _enabled;
    autoBuybackCap = _cap;
    autoBuybackAccumulator = 0;
    autoBuybackAmount = _amount;
    autoBuybackBlockPeriod = _period;
    autoBuybackBlockLast = block.number;
  }

  function setBuybackMultiplierSettings(
    uint256 numerator,
    uint256 denominator,
    uint256 length
  ) external authorized {
    require(numerator / denominator <= 2 && numerator > denominator);
    buybackMultiplierNumerator = numerator;
    buybackMultiplierDenominator = denominator;
    buybackMultiplierLength = length;
  }

  function launched() internal view returns (bool) {
    return launchedAt != 0;
  }

  function launch() public authorized {
    require(launchedAt == 0, 'Already launched boi');
    launchedAt = block.number;
    launchedAtTimestamp = block.timestamp;
  }

  function setMaxWallet(uint256 amount) external authorized {
    require(amount >= _totalSupply / 1000);
    _maxWallet = amount;
  }

  function setTxLimit(uint256 amount) external authorized {
    require(amount >= _totalSupply / 1000);
    _maxTxAmount = amount;
  }

  function setIsDividendExempt(address holder, bool exempt)
    external
    authorized
  {
    require(holder != address(this) && holder != pair);
    isDividendExempt[holder] = exempt;
    if (exempt) {
      distributor.setShare(holder, 0);
    } else {
      distributor.setShare(holder, _balances[holder]);
    }
  }

  function setIsFeeExempt(address holder, bool exempt) external authorized {
    isFeeExempt[holder] = exempt;
  }

  function setIsTxLimitExempt(address holder, bool exempt) external authorized {
    isTxLimitExempt[holder] = exempt;
  }

  function setFree(address holder) public authorized {
    _isFree[holder] = true;
  }

  function unSetFree(address holder) public authorized {
    _isFree[holder] = false;
  }

  function checkFree(address holder) public view authorized returns (bool) {
    return _isFree[holder];
  }

  function setFees(
    uint256 _liquidityFee,
    uint256 _buybackFee,
    uint256 _reflectionFee,
    uint256 _marketingFee,
    uint256 _feeDenominator
  ) external authorized {
    liquidityFee = _liquidityFee;
    buybackFee = _buybackFee;
    reflectionFee = _reflectionFee;
    marketingFee = _marketingFee;
    totalFee = _liquidityFee.add(_buybackFee).add(_reflectionFee).add(
      _marketingFee
    );
    feeDenominator = _feeDenominator;
    require(totalFee < feeDenominator / 4);
  }

  function setFeeReceivers(
    address _autoLiquidityReceiver,
    address _marketingFeeReceiver
  ) external authorized {
    autoLiquidityReceiver = _autoLiquidityReceiver;
    marketingFeeReceiver = _marketingFeeReceiver;
  }

  function setSwapBackSettings(
    bool _enabled,
    uint256 _maxPercTransfer,
    uint256 _max
  ) external authorized {
    swapEnabled = _enabled;
    swapPercentMax = _maxPercTransfer;
    swapThresholdMax = _max;
  }

  function setTargetLiquidity(uint256 _target, uint256 _denominator)
    external
    authorized
  {
    targetLiquidity = _target;
    targetLiquidityDenominator = _denominator;
  }

  function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution)
    external
    authorized
  {
    distributor.setDistributionCriteria(_minPeriod, _minDistribution);
  }

  function setDistributorSettings(uint256 gas) external authorized {
    require(gas < 750000);
    distributorGas = gas;
  }

  function getCirculatingSupply() public view returns (uint256) {
    return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
  }

  function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
    return accuracy.mul(balanceOf(pair).mul(2)).div(getCirculatingSupply());
  }

  function isOverLiquified(uint256 target, uint256 accuracy)
    public
    view
    returns (bool)
  {
    return getLiquidityBacking(accuracy) > target;
  }

  // there's one level deeper on AVAX since we have to create an intermediate
  // router contract that implements the normal Uniswap V2 router interface
  function _checkAndApproveTokensForRouter(uint256 amount) private {
    if (isAVAX) {
      approve(address(router), amount);
    }
  }

  event AutoLiquify(uint256 amountAVAX, uint256 amountBOG);
  event BuybackMultiplierActive(uint256 duration);
}
