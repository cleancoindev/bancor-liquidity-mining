//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./interfaces/ILiquidityProtection.sol";
import "./interfaces/ILiquidityProtectionStore.sol";
import "./interfaces/ITransferPositionCallback.sol";

import "hardhat/console.sol";

contract DappStakingPool is OwnableUpgradeable, ReentrancyGuardUpgradeable, ITransferPositionCallback {
    using SafeMath for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct UserPoolInfo {
        uint amount;
        uint dappStaked;
        uint lpAmount;
        uint pending;
        uint rewardDebt;
        uint positionId;
        uint depositTime;
        uint claimableBnt;
        uint bntLocked;
    }

    struct PoolInfo {
        uint allocPoint;
        uint timeLocked;
        uint lastRewardBlock;
        uint accDappPerShare;
        uint totalDappStaked;
        uint totalDappBntStaked;
        uint totalLpStaked;
    }

    ILiquidityProtection public liquidityProtection;
    ILiquidityProtectionStore public liquidityProtectionStore;

    IERC20Upgradeable public dappToken;
    IERC20Upgradeable public bntToken;

    address public dappBntPoolAnchor;

    uint public dappPerBlock;
    uint public startBlock;
    uint public totalAllocPoint;

    uint public dappILSupply; // amount of DAPP held by contract to cover IL
    uint public dappRewardsSupply; // amount of DAPP held by contract to cover rewards
    uint public pendingBntIlBurn; // BNT to be burned after 24hr lockup

    PoolInfo[] public poolInfo;
    mapping (uint => mapping (address => UserPoolInfo)) public userPoolInfo;
    mapping (uint => uint) public userPoolTotalEntries;

    event DepositDapp(address indexed user, uint indexed pid, uint amount);
    event DepositDappBnt(address indexed user, uint indexed pid, uint amount);
    event withdrawDapp(address indexed user, uint indexed pid, uint amount);
    event withdrawDappBnt(address indexed user, uint indexed pid, uint amount);
    event PositionTransferred(uint256 newId, address indexed provider);

    function initialize(
        address _liquidityProtection,
        address _liquidityProtectionStore,
        address _dappBntPoolAnchor,
        address _dappToken,
        address _bntToken,
        uint _startBlock,
        uint _dappPerBlock
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        liquidityProtection = ILiquidityProtection(_liquidityProtection);
        liquidityProtectionStore = ILiquidityProtectionStore(_liquidityProtectionStore);
        dappBntPoolAnchor = _dappBntPoolAnchor;
        dappToken = IERC20Upgradeable(_dappToken);
        bntToken = IERC20Upgradeable(_bntToken);
        startBlock = _startBlock;
        dappPerBlock = _dappPerBlock;

        dappToken.safeApprove(address(liquidityProtection), uint(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        poolInfo.push(PoolInfo({
            allocPoint: 0,
            timeLocked: 0,
            lastRewardBlock: _startBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
        poolInfo.push(PoolInfo({
            allocPoint: 476,
            timeLocked: 90 days,
            lastRewardBlock: _startBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
        poolInfo.push(PoolInfo({
            allocPoint: 952,
            timeLocked: 120 days,
            lastRewardBlock: _startBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
        poolInfo.push(PoolInfo({
            allocPoint: 1905,
            timeLocked: 240 days,
            lastRewardBlock: _startBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
        poolInfo.push(PoolInfo({
            allocPoint: 2857,
            timeLocked: 540 days,
            lastRewardBlock: _startBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
        poolInfo.push(PoolInfo({
            allocPoint: 3810,
            timeLocked: 720 days,
            lastRewardBlock: _startBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
        // 476 + 952 + 1905 + 2857 + 3810 = 10000
        totalAllocPoint = 10000;
    }

    function getPendingRewards(uint256 pid, address user) external view returns (uint256) {
        UserPoolInfo storage userInfo = userPoolInfo[pid][user];
        PoolInfo storage pool = poolInfo[pid];
        uint accDappPerShare = pool.accDappPerShare;
        if (block.number > pool.lastRewardBlock && pool.totalLpStaked != 0) {
            uint multiplier = (block.number).sub(pool.lastRewardBlock);
            uint dappReward = multiplier.mul(dappPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accDappPerShare = pool.accDappPerShare.add(dappReward.mul(1e12).div(pool.totalLpStaked));
        }
        return userInfo.pending.add(userInfo.amount.mul(accDappPerShare).div(1e12).sub(userInfo.rewardDebt));
    }


    function onTransferPosition(uint256 newId, address provider, bytes calldata data) external override nonReentrant {
        uint pid = abi.decode(data, (uint));
        _updateRewards(pid);

        UserPoolInfo storage userInfo = userPoolInfo[pid][provider];
        PoolInfo storage pool = poolInfo[pid];

        require(userInfo.positionId == 0, "user already has position in pool");
        (address newProvider, address poolToken,, uint lpAmount, uint dappAmount,,,) = liquidityProtectionStore.protectedLiquidity(newId);
        require(address(this) == newProvider);
        require(poolToken == dappBntPoolAnchor, "wrong position type");

        if (userInfo.amount > 0) {
            uint pending = userInfo.amount.mul(pool.accDappPerShare).div(1e12).sub(userInfo.rewardDebt);
            userInfo.pending = userInfo.pending.add(pending);
        } else {
            userPoolTotalEntries[pid]++;
        }

        pool.totalDappStaked = pool.totalDappStaked.add(dappAmount);
        pool.totalLpStaked = pool.totalLpStaked.add(lpAmount);
        userInfo.positionId = newId;
        userInfo.amount = userInfo.amount.add(lpAmount);
        userInfo.dappStaked = userInfo.dappStaked.add(dappAmount);
        userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
        userInfo.depositTime = now;
        emit PositionTransferred(newId, provider);
    }

    // if there is no more bnt for single sided staking, users can still
    // stake dapp-bnt tokens
    function stakeDappBnt(uint amount, uint pid) external nonReentrant {
        _updateRewards(pid);

        UserPoolInfo storage userInfo = userPoolInfo[pid][msg.sender];
        PoolInfo storage pool = poolInfo[pid];

        if (userInfo.amount > 0) {
            uint pending = userInfo.amount.mul(pool.accDappPerShare).div(1e12).sub(userInfo.rewardDebt);
            userInfo.pending = userInfo.pending.add(pending);
        } else {
            userPoolTotalEntries[pid]++;
        }

        amount = _deflationCheck(IERC20Upgradeable(dappBntPoolAnchor), msg.sender, address(this), amount);

        pool.totalLpStaked = pool.totalLpStaked.add(amount);
        pool.totalDappBntStaked = pool.totalDappBntStaked.add(amount);
        userInfo.amount = userInfo.amount.add(amount);
        userInfo.lpAmount = userInfo.lpAmount.add(amount);
        userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
        userInfo.depositTime = now;
    }

    function unstakeDappBnt(uint amount, uint pid) external {
        harvest(pid);
        UserPoolInfo storage userInfo = userPoolInfo[pid][msg.sender];
        PoolInfo storage pool = poolInfo[pid];
        require(userInfo.depositTime + pool.timeLocked <= now, "Still locked");

        pool.totalLpStaked = pool.totalLpStaked.sub(amount);
        pool.totalDappBntStaked = pool.totalDappBntStaked.sub(amount);
        // this line validates user balance
        userInfo.amount = userInfo.amount.sub(amount);
        userInfo.lpAmount = userInfo.lpAmount.sub(amount);
        userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
        IERC20Upgradeable(dappBntPoolAnchor).safeTransfer(msg.sender, amount);
        
        if(userInfo.amount == 0) {
            userPoolTotalEntries[pid]--;
        }
    }

    function stakeDapp(uint amount, uint pid) external {
        _updateRewards(pid);
        UserPoolInfo storage userInfo = userPoolInfo[pid][msg.sender];
        PoolInfo storage pool = poolInfo[pid];
        
        if(userInfo.amount == 0) {
            userPoolTotalEntries[pid]++;
        }

        // If user is staked, we unstake then restake
        if (userInfo.dappStaked > 0) {
            uint pending = userInfo.amount.mul(pool.accDappPerShare).div(1e12).sub(userInfo.rewardDebt);
            userInfo.pending = userInfo.pending.add(pending);
            uint prevDappBal = dappToken.balanceOf(msg.sender);
            _unstakeDapp(pid);
            uint postDappBal = dappToken.balanceOf(msg.sender);
            amount = amount.add(postDappBal).sub(prevDappBal);
            
            amount = _deflationCheck(dappToken, msg.sender, address(this), amount);

            uint positionId = liquidityProtection.addLiquidity(dappBntPoolAnchor, address(dappToken), amount);
            uint lpAmount = _getLpAmount(positionId);
            pool.totalLpStaked = pool.totalLpStaked.add(lpAmount);
            pool.totalDappStaked = pool.totalDappStaked.add(amount);
            userInfo.positionId = positionId;
            userInfo.amount = userInfo.amount.add(lpAmount);
            userInfo.dappStaked = amount;
            userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
            userInfo.depositTime = now;
        } else {
            amount = _deflationCheck(dappToken, msg.sender, address(this), amount);
            uint positionId = liquidityProtection.addLiquidity(dappBntPoolAnchor, address(dappToken), amount);
            uint lpAmount = _getLpAmount(positionId);
            pool.totalLpStaked = pool.totalLpStaked.add(lpAmount);
            pool.totalDappStaked = pool.totalDappStaked.add(amount);
            userInfo.positionId = positionId;
            userInfo.amount = userInfo.amount.add(lpAmount);
            userInfo.dappStaked = amount;
            userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
            userInfo.depositTime = now;
        }
    }

    function unstakeDapp(uint pid) external {
        PoolInfo memory pool = poolInfo[pid];
        UserPoolInfo memory userInfo = userPoolInfo[pid][msg.sender];
        require(userInfo.depositTime + pool.timeLocked <= now, "Still locked");
        _unstakeDapp(pid);
    }

    function harvest(uint pid) public nonReentrant {
        _updateRewards(pid);
        UserPoolInfo storage userInfo = userPoolInfo[pid][msg.sender];
        PoolInfo storage pool = poolInfo[pid];
        uint pendingReward = userInfo.pending.add(userInfo.amount.mul(pool.accDappPerShare).div(1e12).sub(userInfo.rewardDebt));
        if(pendingReward > 0) {
            if (dappRewardsSupply > pendingReward) {
                dappRewardsSupply = dappRewardsSupply.sub(pendingReward);
                userInfo.pending = 0;
                userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
                dappToken.safeTransfer(msg.sender, pendingReward);
            } else {
                dappRewardsSupply = 0;
                userInfo.pending = pendingReward.sub(dappRewardsSupply);
                userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);
                dappToken.safeTransfer(msg.sender, dappRewardsSupply);
            }
        }
    }

    function fund(uint dappRewardsAmount, uint dappILAmount) external nonReentrant {
        dappRewardsAmount = _deflationCheck(dappToken, msg.sender, address(this), dappRewardsAmount);
        dappILAmount = _deflationCheck(dappToken, msg.sender, address(this), dappILAmount);
        dappRewardsSupply = dappRewardsSupply.add(dappRewardsAmount);
        dappILSupply = dappILSupply.add(dappILAmount);
    }

    function add(uint256 _allocPoint, uint256 _timeLocked) external onlyOwner {
        _updatePools();
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            allocPoint: _allocPoint,
            timeLocked: _timeLocked,
            lastRewardBlock: lastRewardBlock,
            accDappPerShare: 0,
            totalDappStaked: 0,
            totalDappBntStaked: 0,
            totalLpStaked: 0
        }));
    }

    function set(uint256 pid, uint256 _allocPoint) external onlyOwner {
        _updatePools();
        uint256 prevAllocPoint = poolInfo[pid].allocPoint;
        poolInfo[pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    function setDappPerBlock(uint _dappPerBlock) external onlyOwner {
        _updatePools();
        dappPerBlock = _dappPerBlock;
    }

    // user must wait 24 hours for BNT to unlock, after can call and receive
    function claimUserBnt(uint pid) external nonReentrant {
        UserPoolInfo storage userInfo = userPoolInfo[pid][msg.sender];
        require(userInfo.bntLocked <= now, "BNT still locked");
        uint bntBal = bntToken.balanceOf(address(this));
        uint amount = userInfo.claimableBnt;
        require(bntBal >= amount, "insufficient bnt to claim");
        userInfo.claimableBnt = 0;
        userInfo.bntLocked = 0;
        bntToken.safeTransfer(msg.sender, amount);
    }

    // user must wait 24 hours for BNT to unlock, after can call and receive
    function claimBnt(uint num) external nonReentrant {
        liquidityProtection.claimBalance(0, num + 1);
    }

    // if pending bnt to burn, burn
    function burnBnt() external nonReentrant {
        require(pendingBntIlBurn > 0, "no pending bnt to burn");
        uint bntBal = bntToken.balanceOf(address(this));
        if(bntBal >= pendingBntIlBurn) {
            bntToken.safeTransfer(address(0x000000000000000000000000000000000000dEaD), pendingBntIlBurn);
            pendingBntIlBurn = 0;
        } else {
            pendingBntIlBurn = pendingBntIlBurn.sub(bntBal);
            bntToken.safeTransfer(address(0x000000000000000000000000000000000000dEaD), bntBal);
        }
    }

    function _getLpAmount(uint positionId) private view returns (uint) {
        (,,, uint lpAmount,,,,) = liquidityProtectionStore.protectedLiquidity(positionId);
        return lpAmount;
    }

    function _deflationCheck(IERC20Upgradeable token, address from, address to, uint amount) private returns (uint) {
        uint prevDappBal = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        uint postDappBal = token.balanceOf(to);
        return postDappBal.sub(prevDappBal);
    }

    function _updateRewards(uint pid) private {
        PoolInfo storage pool = poolInfo[pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.totalLpStaked == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint multiplier = (block.number).sub(pool.lastRewardBlock);
        uint dappReward = multiplier.mul(dappPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accDappPerShare = pool.accDappPerShare.add(dappReward.mul(1e12).div(pool.totalLpStaked));
        pool.lastRewardBlock = block.number;
    }

    function _updatePools() private {
        uint length = poolInfo.length;
        for(uint pid = 0; pid < length; ++pid) {
            _updateRewards(pid);
        }
    }

    function _unstakeDapp(uint pid) private {
        harvest(pid);
        UserPoolInfo storage userInfo = userPoolInfo[pid][msg.sender];
        PoolInfo storage pool = poolInfo[pid];

        uint prevLpAmount = _getLpAmount(userInfo.positionId);
        uint preDappBal = dappToken.balanceOf(address(this));

        (uint targetAmount,, uint networkAmount) = liquidityProtection.removeLiquidityReturn(userInfo.positionId, 1000000, block.timestamp);
        liquidityProtection.removeLiquidity(userInfo.positionId, 1000000);

        uint postDappBal = dappToken.balanceOf(address(this));
        uint dappReceived = postDappBal.sub(preDappBal);

        pool.totalLpStaked = pool.totalLpStaked.sub(prevLpAmount);
        pool.totalDappStaked = pool.totalDappStaked.sub(userInfo.dappStaked);
        userInfo.amount = userInfo.amount.sub(prevLpAmount);
        userInfo.rewardDebt = userInfo.amount.mul(pool.accDappPerShare).div(1e12);

        uint finalDappAmount = targetAmount < userInfo.dappStaked ? targetAmount : userInfo.dappStaked;

        if(finalDappAmount > dappReceived) {
            uint diff = finalDappAmount.sub(dappReceived);
            if (dappILSupply >= diff) {
                pendingBntIlBurn = pendingBntIlBurn.add(networkAmount);
                dappILSupply = dappILSupply.sub(diff);
                dappToken.safeTransfer(msg.sender, finalDappAmount);
            } else {
                userInfo.claimableBnt = userInfo.claimableBnt.add(networkAmount);
                userInfo.bntLocked = now + 24 hours;
                dappToken.safeTransfer(msg.sender, dappReceived.add(dappILSupply));
                dappILSupply = 0;
            }
        } else {
            pendingBntIlBurn = pendingBntIlBurn.add(networkAmount);
            dappToken.safeTransfer(msg.sender, dappReceived);
        }

        userInfo.dappStaked = 0;
        userInfo.positionId = 0;
        
        if(userInfo.amount == 0) {
            userPoolTotalEntries[pid]--;
        }
    }
}