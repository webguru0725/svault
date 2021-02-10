// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

interface NoMintRewardPool {
    function getReward() external;
    function stake(uint amount) external;
    function withdraw(uint amount) external;
}

interface VaultProxy {
    function approve(address spender, uint amount) external returns (bool);
    function deposit(uint amount) external;
    function withdraw(uint amount) external;
    function balanceOf(address account) external returns (uint);
    function underlyingBalanceWithInvestment() external returns (uint);
    function totalSupply() external returns (uint);
}

interface UniswapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory);
}

contract Svault {

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    NoMintRewardPool constant HARVESTPOOL = NoMintRewardPool(0x6D1b6Ea108AA03c6993d8010690264BA96D349A8);
    VaultProxy constant FYCRV = VaultProxy(0x0FE4283e0216F94f5f9750a7a11AC54D3c9C38F3);
    IERC20 constant FARM = IERC20(0xa0246c9032bC3A600820415aE600c6388619A14D);
    UniswapRouter constant UNIROUTER = UniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uint32 constant TOTALRATE = 10000;
    
    mapping(address => uint) public rewardedBalancePerUser;
    mapping(address => uint) public lastTimestampPerUser;
    mapping(address => uint) public depositBalancePerUser;
    mapping(address => uint) public accDepositBalancePerUser;

    uint public lastTotalTimestamp;
    uint public accTotalReward;
    uint public totalDeposit;
    uint public accTotalDeposit;

    string public vaultName;
    IERC20 public token0;
    IERC20 public token1;


    address public feeAddress;

    uint32 public feeRate;

    address public treasury;


    uint32 public rewardUserRate = 7000;
    uint32 public rewardTreasuryRate = 1500;

    
    address public gov;

    event Deposited(address indexed user, uint amount);
    event ClaimedReward(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);

    constructor (address _token0, address _token1, address _feeAddress, string memory name, address _treasury) payable {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        feeAddress = _feeAddress;
        vaultName = name;
        gov = msg.sender;
        treasury = _treasury;
        token0.approve(address(FYCRV), type(uint).max);
        FYCRV.approve(address(HARVESTPOOL), type(uint).max);
        FARM.approve(address(UNIROUTER), type(uint).max);
    }

    modifier onlyGov() {
        require(msg.sender == gov, "!governance");
        _;
    }

    modifier updateBalance(address userAddress) {
        uint lastTimestamp = lastTimestampPerUser[userAddress];
        uint totalTimestamp = lastTotalTimestamp;
        if (lastTimestamp > 0) {
            accDepositBalancePerUser[userAddress] += depositBalancePerUser[userAddress] * (block.timestamp - lastTimestamp);
        }

        if (totalTimestamp > 0) {
            accTotalDeposit += totalDeposit * (block.timestamp - totalTimestamp);
        }
        lastTimestampPerUser[userAddress] = block.timestamp;
        lastTotalTimestamp = block.timestamp;
        _;
    }

    function setGovernance(address _gov)
        external
        onlyGov
    {
        gov = _gov;
    }

    function setToken0(address _token)
        external
        onlyGov
    {
        token0 = IERC20(_token);
    }

    function setToken1(address _token)
        external
        onlyGov
    {
        token1 = IERC20(_token);
    }

    function setTreasury(address _treasury)
        external
        onlyGov
    {
        treasury = _treasury;
    }

    function setUserRate(uint32 _rewardUserRate)
        external
        onlyGov
    {
        rewardUserRate = _rewardUserRate;
    }

    function setTreasuryRate(uint32 _rewardTreasuryRate)
        external
        onlyGov
    {
        rewardTreasuryRate = _rewardTreasuryRate;
    }

    function setFeeAddress(address _feeAddress)
        external
        onlyGov
    {
        feeAddress = _feeAddress;
    }

    function setFeeRate(uint32 _feeRate)
        external
        onlyGov
    {
        feeRate = _feeRate;
    }

    function setVaultName(string memory name)
        external
        onlyGov
    {
        vaultName = name;
    }

    function getReward() internal
    {
        uint rewardAmountForFarmToken = FARM.balanceOf(address(this));
        HARVESTPOOL.getReward();
        rewardAmountForFarmToken = FARM.balanceOf(address(this)) - rewardAmountForFarmToken;
        uint rewardFarmTokenAmountForUsers = rewardAmountForFarmToken * rewardUserRate / TOTALRATE;
        uint rewardFarmTokenAmountForTreasury = rewardAmountForFarmToken * rewardTreasuryRate / TOTALRATE;
        uint rewardFarmTokenAmountForAutoDeposit = rewardAmountForFarmToken - rewardFarmTokenAmountForUsers - rewardFarmTokenAmountForTreasury;
        address[] memory tokens = new address[](3);
        tokens[0] = address(FARM);
        tokens[1] = address(WETH);
        tokens[2] = address(token1);
        address[] memory tokens1 = new address[](2);
        tokens[0] = address(FARM);
        tokens[1] = address(WETH);
        address[] memory tokens2 = new address[](3);
        tokens2[0] = address(FARM);
        tokens2[1] = address(WETH);
        tokens2[2] = address(token0);
        uint rewardPylonTokenAmountForUsers = token1.balanceOf(address(this));
        uint autoDepositYCRVAmount = token0.balanceOf(address(this));
        if (rewardFarmTokenAmountForUsers > 0) {
            UNIROUTER.swapExactTokensForTokens(rewardFarmTokenAmountForUsers, 0, tokens, address(this), type(uint).max);
        }
        if (rewardFarmTokenAmountForTreasury > 0) {
            UNIROUTER.swapExactTokensForTokens(rewardFarmTokenAmountForTreasury, 0, tokens1, address(this), type(uint).max);
        }
        if (rewardFarmTokenAmountForAutoDeposit > 0) {
            UNIROUTER.swapExactTokensForTokens(rewardFarmTokenAmountForAutoDeposit, 0, tokens2, address(this), type(uint).max);
        }
        rewardPylonTokenAmountForUsers = token1.balanceOf(address(this)) - rewardPylonTokenAmountForUsers; // fYCRV -> Pylon   from rewardFarmTokenAmountForUsers
        autoDepositYCRVAmount = token0.balanceOf(address(this)) - autoDepositYCRVAmount; // fYCRV -> YCRV from rewardAmountForFarmToken-rewardFarmTokenAmountForUsers-rewardFarmTokenAmountForTreasury
        uint autoDepositfYCRVAmount = 0;
        if (autoDepositYCRVAmount > 0) {
            autoDepositfYCRVAmount = FYCRV.balanceOf(address(this));
            FYCRV.deposit(autoDepositYCRVAmount);
            autoDepositfYCRVAmount = FYCRV.balanceOf(address(this)) - autoDepositfYCRVAmount;
        }
        if (autoDepositfYCRVAmount > 0) {
            HARVESTPOOL.stake(autoDepositfYCRVAmount);
        }
        uint wethBalance = WETH.balanceOf(address(this));
        if (wethBalance > 0) {
            WETH.transfer(treasury, wethBalance);
        }
    }

    function deposit(uint amount) external updateBalance(msg.sender) {
        getReward();

        uint feeAmount = amount * feeRate / 10000;
        uint realAmount = amount - feeAmount;

        if (feeAmount > 0) {
            token0.transferFrom(msg.sender, feeAddress, feeAmount);
        }
        
        if (realAmount > 0) {
            token0.transferFrom(msg.sender, address(this), realAmount);
            FYCRV.deposit(realAmount);
            uint depositAmountForHarvest = FYCRV.balanceOf(address(this));
            HARVESTPOOL.stake(depositAmountForHarvest);
            depositBalancePerUser[msg.sender] += realAmount;
            totalDeposit += realAmount;
            emit Deposited(msg.sender, realAmount);
        }
    }

    function withdraw(uint amount) external updateBalance(msg.sender) {
        getReward();

        uint amountWithdrawForFYCRV = amount * FYCRV.totalSupply() / FYCRV.underlyingBalanceWithInvestment();
        HARVESTPOOL.withdraw(amountWithdrawForFYCRV);
        FYCRV.withdraw(amountWithdrawForFYCRV);
        uint amountWithdrawForYCRV = token0.balanceOf(address(this));
        require(amountWithdrawForYCRV > 0, "no withdraw amount");
        token0.transfer(msg.sender, amountWithdrawForYCRV);
        
        uint depositBalance = depositBalancePerUser[msg.sender];
        if (amount > depositBalance) {
            amount = depositBalance;
        }

        require(amount > 0, "can't withdraw 0");
        
        depositBalancePerUser[msg.sender] = depositBalance - amountWithdrawForYCRV;
        totalDeposit -= amountWithdrawForYCRV;

        emit Withdrawn(msg.sender, amountWithdrawForYCRV);
    }

    function claimReward() external updateBalance(msg.sender) {
        getReward();

        uint reward = 0;
        uint currentRewardAmount = accTotalReward * accDepositBalancePerUser[msg.sender] / accTotalDeposit;
        uint rewardedAmount = rewardedBalancePerUser[msg.sender];
        if (currentRewardAmount > rewardedAmount) {
            reward = currentRewardAmount - rewardedAmount;
            rewardedBalancePerUser[msg.sender] = rewardedAmount + reward;
            uint token1Balance = token1.balanceOf(address(this));
            if (reward > token1Balance) {
                reward = token1Balance;
            }
        }
        if (reward > 0) {
            token1.transfer(msg.sender, reward);
        }
    }

    function seize(address token, address to) external onlyGov {
        require(IERC20(token) != token0 && IERC20(token) != token1, "main tokens");
        if (token != address(0)) {
            uint amount = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(to, amount);
        }
        else {
            uint amount = address(this).balance;
            payable(to).transfer(amount);
        }
    }
        
    fallback () external payable { }
    receive () external payable { }
}