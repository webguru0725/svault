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

interface UniswapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

interface YCrvGauge {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function integrate_fraction(address account) external view returns (uint256);
    function user_checkpoint(address account) external returns (bool);
    function crv_token() external view returns (address);
    function controller() external view returns (address);
    function period() external view returns (uint256);
    function period_timestamp(uint256 amount) external view returns (uint256);
    function integrate_inv_supply(uint256 amount) external view returns (uint256);
    function integrate_inv_supply_of(address account) external view returns (uint256);
    function inflation_rate() external view returns (uint256);
    function future_epoch_time() external view returns (uint256);
    function working_balances(address account) external view returns (uint256);
    function working_supply() external view returns (uint256);
}

interface Controller {
    function gauge_relative_weight(address account, uint256 time) external view returns (uint256);
}

interface CRV20 {
    function rate() external view returns (uint256);
}

interface TokenMinter {
    function mint(address account) external;
    function minted(address account, address guage) external view returns (uint256);
}

contract Svault {

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    UniswapRouter constant UNIROUTER = UniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    YCrvGauge constant YCRVGAUGE = YCrvGauge(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1);
    TokenMinter constant TOKENMINTER = TokenMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    uint32 constant TOTALRATE = 10000;
    IERC20 constant CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    uint256 constant WEEK = 604800;
    
    mapping(address => uint) public rewardedBalancePerUser;
    mapping(address => uint) public lastTimestampPerUser;
    mapping(address => uint) public depositBalancePerUser;
    mapping(address => uint) public accDepositBalancePerUser;

    uint public lastTotalTimestamp;
    uint public accTotalReward;
    uint public totalDeposit;
    uint public accTotalDeposit;
    uint public totalDepositForAPY;

    string public vaultName;
    IERC20 public token0;
    IERC20 public token1;

    address public feeAddress;

    uint32 public feeRate;

    address public treasury;


    uint32 public rewardUserRate = 7000;
    uint32 public rewardTreasuryRate = 3000;

    
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
        token0.approve(address(YCRVGAUGE), type(uint).max);
        CRV.approve(address(UNIROUTER), type(uint).max);
    }

    modifier onlyGov() {
        require(msg.sender == gov, "!governance");
        _;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        if(a > b)
        {
            return b;
        }else{
            return a;
        }
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
        uint rewardAmountForCRVToken = CRV.balanceOf(address(this));
        TOKENMINTER.mint(address(YCRVGAUGE));
        rewardAmountForCRVToken = CRV.balanceOf(address(this)) - rewardAmountForCRVToken;
        uint rewardCRVTokenAmountForUsers = rewardAmountForCRVToken * rewardUserRate / TOTALRATE;
        uint rewardCRVTokenAmountForTreasury = rewardAmountForCRVToken * rewardTreasuryRate / TOTALRATE;
        address[] memory tokens = new address[](3);
        tokens[0] = address(CRV);
        tokens[1] = address(WETH);
        tokens[2] = address(token1);
        address[] memory tokens1 = new address[](2);
        tokens1[0] = address(CRV);
        tokens1[1] = address(WETH);
        uint rewardPylonTokenAmountForUsers = token1.balanceOf(address(this));
        if (rewardCRVTokenAmountForUsers > 0) {
            UNIROUTER.swapExactTokensForTokens(rewardCRVTokenAmountForUsers, 0, tokens, address(this), type(uint).max);
        }
        uint wethBalance = WETH.balanceOf(address(this));
        if (rewardCRVTokenAmountForTreasury > 0) {
            UNIROUTER.swapExactTokensForTokens(rewardCRVTokenAmountForTreasury, 0, tokens1, address(this), type(uint).max);
        }
    
        rewardPylonTokenAmountForUsers = token1.balanceOf(address(this)) - rewardPylonTokenAmountForUsers; // fYCRV -> Pylon   from rewardFarmTokenAmountForUsers
        accTotalReward += rewardPylonTokenAmountForUsers;
        wethBalance = WETH.balanceOf(address(this)) - wethBalance;
        if (wethBalance > 0) {
            WETH.transfer(treasury, wethBalance);
        }
    }

    function getRewardAmount(address userAddress) public view returns (uint256) {
        uint256 _period = YCRVGAUGE.period();
        uint256 _period_time = YCRVGAUGE.period_timestamp(_period);
        uint256 _integrate_inv_supply = YCRVGAUGE.integrate_inv_supply(_period);
        uint256 rate = YCRVGAUGE.inflation_rate();
        uint256 new_rate = rate;
        uint256 prev_future_epoch = YCRVGAUGE.future_epoch_time();
        if (prev_future_epoch >= _period_time)
        {
            new_rate = CRV20(YCRVGAUGE.crv_token()).rate();
        }
        uint256 _working_balance = YCRVGAUGE.working_balances(address(this));
        uint256 _working_supply = YCRVGAUGE.working_supply();

        if (block.timestamp > _period_time)
        {
            uint256 prev_week_time = _period_time;
            uint256 week_time = min((_period_time + WEEK) / WEEK * WEEK, block.timestamp);
            for(uint i; i < 500; i++)
            {
                uint256 dt = week_time - prev_week_time;
                uint256 w = Controller(YCRVGAUGE.controller()).gauge_relative_weight(address(YCRVGAUGE), prev_week_time / WEEK * WEEK);
          
                if (prev_future_epoch >= prev_week_time && prev_future_epoch < week_time)
                {
                    _integrate_inv_supply += rate * w * (prev_future_epoch - prev_week_time) / _working_supply;
                    rate = new_rate;
                    _integrate_inv_supply += rate * w * (week_time - prev_future_epoch) / _working_supply;
                }
                else{
                    _integrate_inv_supply += rate * w * dt / _working_supply;
                }
                if (week_time == block.timestamp) break;
                prev_week_time = week_time;
                week_time = min(week_time + WEEK, block.timestamp);
            }
        }
        _period += 1;
        uint256 integrate_fraction = YCRVGAUGE.integrate_fraction(address(this));
        integrate_fraction += _working_balance * (_integrate_inv_supply - YCRVGAUGE.integrate_inv_supply_of(address(this))) / 10 ** 18;
        uint rewardAmountForCRVToken = integrate_fraction - TOKENMINTER.minted(address(this), address(YCRVGAUGE));

        uint rewardCRVTokenAmountForUsers = rewardAmountForCRVToken * rewardUserRate / TOTALRATE;
        address[] memory tokens = new address[](3);
        tokens[0] = address(CRV);
        tokens[1] = address(WETH);
        tokens[2] = address(token1);
        uint[] memory availablePylonRewardAmountsForUsers = new uint[](3);
        availablePylonRewardAmountsForUsers = UNIROUTER.getAmountsOut(rewardCRVTokenAmountForUsers, tokens);
        uint256 availablePylonRewardAmountForUsers = availablePylonRewardAmountsForUsers[2];
        uint256 availablePylonRewardAmountForUser = availablePylonRewardAmountForUsers * accDepositBalancePerUser[userAddress] / accTotalDeposit;
        return availablePylonRewardAmountForUser;
    }

    function deposit(uint amount) external updateBalance(msg.sender) {
        uint feeAmount = amount * feeRate / TOTALRATE;
        uint realAmount = amount - feeAmount;

        if (feeAmount > 0) {
            token0.transferFrom(msg.sender, feeAddress, feeAmount);
        }
        
        if (realAmount > 0) {
            token0.transferFrom(msg.sender, address(this), realAmount);
            YCRVGAUGE.deposit(realAmount);
            depositBalancePerUser[msg.sender] += realAmount;
            totalDeposit += realAmount;
            totalDepositForAPY += realAmount;
            emit Deposited(msg.sender, realAmount);
        }
    }

    function withdraw(uint amount) external updateBalance(msg.sender) {
        uint depositBalance = depositBalancePerUser[msg.sender];
        if (amount > depositBalance) {
            amount = depositBalance;
        }
        uint amountWithdrawForYCRV = token0.balanceOf(address(this));
        YCRVGAUGE.withdraw(amount);
        amountWithdrawForYCRV = token0.balanceOf(address(this)) - amountWithdrawForYCRV;
        token0.transfer(msg.sender, amountWithdrawForYCRV);
        
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
            emit ClaimedReward(msg.sender, reward);
        }
    }

    function seize(address token, address to) external onlyGov {
        require(IERC20(token) != token1, "main tokens");
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