// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface NoMintRewardPool {
    function getReward() external;
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

interface VaultProxy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external returns (uint256);
    function underlyingBalanceWithInvestment() external returns (uint256);
    function totalSupply() external returns (uint256);
}

interface UniswapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    function toPayable(address account) internal pure returns (address payable) {
        return payable(account);
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call{ value : amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

contract Svault {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    mapping(address => uint256) public _rewardBalance;
    mapping(address => uint256) public _depositBalances;

    uint256 public _totalDeposit;

    string public _vaultName;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public rewardTokenComesfromHarvest = IERC20(0xa0246c9032bC3A600820415aE600c6388619A14D);
    IERC20 public WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public feeAddress;
    address public vaultAddress;
    uint32 public feePermill;
    bool public withdrawable;
    uint256 public totalRate = 10000;
    address public treasury;
    NoMintRewardPool harvestAddress = NoMintRewardPool(0x6D1b6Ea108AA03c6993d8010690264BA96D349A8);
    VaultProxy fycrvContract = VaultProxy(0x0FE4283e0216F94f5f9750a7a11AC54D3c9C38F3);
    UniswapRouter uniswapRouter = UniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uint256 public rewardUserRate = 7000;
    uint256 public rewardTreasuryRate = 1500;

    
    address public gov;

    uint256 public _rewardCount;

    event SentReward(uint256 amount);
    event Deposited(address indexed user, uint256 amount);
    event ClaimedReward(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor (address _token0, address _token1, address _feeAddress, address _vaultAddress, string memory name, address _treasury) payable {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        feeAddress = _feeAddress;
        vaultAddress = _vaultAddress;
        _vaultName = name;
        gov = msg.sender;
        treasury = _treasury;
        token0.approve(0x0FE4283e0216F94f5f9750a7a11AC54D3c9C38F3, 2 ** 256 - 1);
        IERC20(0x0FE4283e0216F94f5f9750a7a11AC54D3c9C38F3).approve(0x6D1b6Ea108AA03c6993d8010690264BA96D349A8, 2 ** 256 - 1);
    }

    modifier onlyGov() {
        require(msg.sender == gov, "!governance");
        _;
    }

    function setGovernance(address _gov)
        external
        onlyGov
    {
        gov = _gov;
    }

    function setWETHAddress(address _token)
        external
        onlyGov
    {
        WETH = IERC20(_token);
    }

    function setToken0(address _token)
        external
        onlyGov
    {
        token0 = IERC20(_token);
    }

    function setRewardTokenComesFromHarvest(address _token)
        external
        onlyGov
    {
        rewardTokenComesfromHarvest = IERC20(_token);
    }

    function setTotalRate(uint256 _totalRate)
        external
        onlyGov
    {
        totalRate = _totalRate;
    }

    function setTreasury(address _treasury)
        external
        onlyGov
    {
        treasury = _treasury;
    }

    function setUserRate(uint256 _rewardUserRate)
        external
        onlyGov
    {
        rewardUserRate = _rewardUserRate;
    }

    function setTreasuryRate(uint256 _rewardTreasuryRate)
        external
        onlyGov
    {
        rewardTreasuryRate = _rewardTreasuryRate;
    }

    function setToken1(address _token)
        external
        onlyGov
    {
        token1 = IERC20(_token);
    }

    function setFeeAddress(address _feeAddress)
        external
        onlyGov
    {
        feeAddress = _feeAddress;
    }

    function setVaultAddress(address _vaultAddress)
        external
        onlyGov
    {
        vaultAddress = _vaultAddress;
    }

    function setFeePermill(uint32 _feePermill)
        external
        onlyGov
    {
        feePermill = _feePermill;
    }

    function setWithdrawable(bool _withdrawable)
        external
        onlyGov
    {
        withdrawable = _withdrawable;
    }

    function setVaultName(string memory name)
        external
        onlyGov
    {
        _vaultName = name;
    }

    function balance0()
        external
        view
        returns (uint256)
    {
        return token0.balanceOf(address(this));
    }

    function balance1()
        external
        view
        returns (uint256)
    {
        return token1.balanceOf(address(this));
    }

    function getReward(address userAddress)
        internal
    {
        uint256 rewardBalance = _rewardBalance[userAddress];

        harvestAddress.getReward();
        uint256 rewardAmountForFarmToken = rewardTokenComesfromHarvest.balanceOf(address(this));
        uint256 rewardFarmTokenAmountForUsers = rewardAmountForFarmToken.mul(rewardUserRate).div(totalRate);
        uint256 rewardFarmTokenAmountForTreasury = rewardAmountForFarmToken.mul(rewardTreasuryRate).div(totalRate);
        uint256 rewardFarmTokenAmountForAutoDeposit = rewardAmountForFarmToken.sub(rewardFarmTokenAmountForUsers).sub(rewardFarmTokenAmountForTreasury);
        address[] memory tokens = new address[](3);
        tokens[0] = address(rewardTokenComesfromHarvest);
        tokens[1] = address(WETH);
        tokens[2] = address(token1);
        address[] memory tokens2 = new address[](3);
        tokens2[0] = address(rewardTokenComesfromHarvest);
        tokens2[1] = address(WETH);
        tokens2[2] = address(token0);
        rewardTokenComesfromHarvest.approve(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, rewardAmountForFarmToken);
        uniswapRouter.swapExactTokensForTokens(rewardFarmTokenAmountForUsers, 0, tokens, address(this), 2 ** 256 -1);
        uniswapRouter.swapExactTokensForTokens(rewardFarmTokenAmountForAutoDeposit, 0, tokens2, address(this), 2 ** 256 -1);
        uint256 rewardPylonTokenAmountForUsers = token1.balanceOf(address(this)); // fYCRV -> Pylon   from rewardFarmTokenAmountForUsers
        uint256 autoDepositYCRVAmount = token0.balanceOf(address(this)); // fYCRV -> YCRV from rewardAmountForFarmToken-rewardFarmTokenAmountForUsers-rewardFarmTokenAmountForTreasury
        fycrvContract.deposit(autoDepositYCRVAmount);
        uint256 autoDepositfYCRVAmount = fycrvContract.balanceOf(address(this));
        harvestAddress.stake(autoDepositfYCRVAmount); //auto deposit again
        _depositBalances[userAddress] = _depositBalances[userAddress].add(autoDepositYCRVAmount);
        _totalDeposit = _totalDeposit.add(autoDepositYCRVAmount);
        
        rewardTokenComesfromHarvest.safeTransfer(treasury, rewardFarmTokenAmountForTreasury);
        
        uint256 rewardRateOneUser = _depositBalances[userAddress].div(_totalDeposit);
        rewardBalance = rewardBalance.add(rewardPylonTokenAmountForUsers.mul(rewardRateOneUser));
           
        _rewardBalance[userAddress] = rewardBalance;
    }

    function deposit(uint256 amount) external {
        // getReward(msg.sender);
        uint256 feeAmount = amount.mul(feePermill).div(1000);
        uint256 realAmount = amount.sub(feeAmount);

        if (feeAmount > 0) {
            token0.safeTransferFrom(msg.sender, feeAddress, feeAmount);
        }
        if (realAmount > 0) {
            token0.safeTransferFrom(msg.sender, address(this), realAmount);
            fycrvContract.deposit(realAmount);
            uint256 depositAmountForHarvest = fycrvContract.balanceOf(address(this));
            harvestAddress.stake(depositAmountForHarvest);
            
            _depositBalances[msg.sender] = _depositBalances[msg.sender].add(realAmount);
            _totalDeposit = _totalDeposit.add(realAmount);
            emit Deposited(msg.sender, realAmount);
        }
    }

    function withdraw(uint256 amount) external {
        // require(amount == 1000000000000000000, "can't withdraw 0");
        uint256 amountWithdrawForFYCRV = amount.mul(fycrvContract.totalSupply()).div(fycrvContract.underlyingBalanceWithInvestment());
        harvestAddress.withdraw(amountWithdrawForFYCRV);
        fycrvContract.withdraw(amountWithdrawForFYCRV);
        uint256 amountWithdrawForYCRV = token0.balanceOf(address(this));

        require(token0.balanceOf(address(this)) > 0, "no withdraw amount");
        require(withdrawable, "not withdrawable");
        token0.transfer(msg.sender, amountWithdrawForYCRV);
        getReward(msg.sender);

        if (amount > _depositBalances[msg.sender]) {
            amount = _depositBalances[msg.sender];
        }

        require(amount > 0, "can't withdraw 0");
        // require(amountWithdrawForYCRV > 0, "can't withdraw YCRV 0");
        // require(amountWithdrawForYCRV == amount, "not match");

        

        // _depositBalances[msg.sender] = _depositBalances[msg.sender].sub(amount);
        // _totalDeposit = _totalDeposit.sub(amount);

        // emit Withdrawn(msg.sender, amount);
    }

    function claimReward(uint256 amount) external {
        getReward(msg.sender);

        uint256 rewardLimit = _rewardBalance[msg.sender];

        if (amount > rewardLimit) {
            amount = rewardLimit;
        }
        _rewardBalance[msg.sender] = _rewardBalance[msg.sender].sub(amount);
        token1.safeTransfer(msg.sender, amount);
    }

    function claimRewardAll() external {
        getReward(msg.sender);
        
        uint256 rewardLimit = _rewardBalance[msg.sender];
        
        _rewardBalance[msg.sender] = _rewardBalance[msg.sender].sub(rewardLimit);
        token1.safeTransfer(msg.sender, rewardLimit);
    }
    
    function seize(address token, address to) external onlyGov {
        require(IERC20(token) != token0 && IERC20(token) != token1, "main tokens");
        if (token != address(0)) {
            uint256 amount = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(to, amount);
        }
        else {
            uint256 amount = address(this).balance;
            payable(to).transfer(amount);
        }
    }
        
    fallback () external payable { }
    receive () external payable { }
}