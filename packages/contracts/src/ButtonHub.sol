// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ButtonHubSkeleton is ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct StartParams {
    address token;
    uint256 basePrice;
    uint64 roundDuration;
    uint16 devFeeBps;
    uint16 treasuryFeeBps;
    address dev;
    address treasury;
    uint8 pricingModel; // 0=fixed,1=cliff
    bytes pricingData; // abi-encoded curve params
    bytes32 retroConfigHash;
    bytes32 vaultId;
    uint256 seedAmount;
  }

  struct Round {
    address token;
    uint256 basePrice;
    uint64 roundDuration;
    uint64 deadline;
    uint64 startTime;
    uint64 endTime;
    uint16 devFeeBps;
    uint16 treasuryFeeBps;
    address dev;
    address treasury;
    address currentWinner;
    uint256 pot;
    uint256 plays;
    uint8 pricingModel;
    uint256 priceState;
    bytes pricingData;
    bool ended;
    bool finalized;
    bytes32 retroConfigHash;
    bytes32 vaultId;
  }

  uint256 public nextRoundId;
  mapping(uint256 => Round) public rounds;

  event RoundStarted(
    address indexed token,
    uint256 indexed roundId,
    StartParams params,
    uint64 startTime,
    uint64 deadline
  );

  event Play(
    uint256 indexed roundId,
    address indexed player,
    uint256 pricePaid,
    uint256 potAfter,
    uint64 newDeadline
  );

  event RoundEnded(uint256 indexed roundId, address winner, uint64 endTime);

  event Finalized(
    uint256 indexed roundId,
    address indexed winner,
    uint256 potPaid,
    uint256 devPaid,
    uint256 treasuryPaid
  );

  function startRound(StartParams calldata p) external nonReentrant returns (uint256 id) {
    require(p.token != address(0), "token");
    require(p.basePrice > 0, "price");
    require(p.roundDuration >= 30 && p.roundDuration <= 86400, "duration");
    require(p.devFeeBps + p.treasuryFeeBps <= 10000, "fees");

    id = ++nextRoundId;
    Round storage r = rounds[id];
    r.token = p.token;
    r.basePrice = p.basePrice;
    r.roundDuration = p.roundDuration;
    r.deadline = uint64(block.timestamp + p.roundDuration);
    r.startTime = uint64(block.timestamp);
    r.devFeeBps = p.devFeeBps;
    r.treasuryFeeBps = p.treasuryFeeBps;
    r.dev = p.dev;
    r.treasury = p.treasury;
    r.pricingModel = p.pricingModel;
    r.pricingData = p.pricingData;
    r.retroConfigHash = p.retroConfigHash;
    r.vaultId = p.vaultId;

    if (p.seedAmount > 0) {
      IERC20(p.token).safeTransferFrom(msg.sender, address(this), p.seedAmount);
      r.pot += p.seedAmount;
    }

    emit RoundStarted(p.token, id, p, r.startTime, r.deadline);
  }

  function getCurrentPrice(uint256 id) public view returns (uint256) {
    Round storage r = rounds[id];
    if (r.pricingModel == 0) {
      return r.basePrice;
    }
    if (r.pricingModel == 1) {
      // cliff: abi.decode to (cliffSize, incrementBpsPerCliff, maxMarkupBps)
      (uint256 cliffSize, uint256 incBps, uint256 maxBps) =
        abi.decode(r.pricingData, (uint256, uint256, uint256));
      uint256 cliffs = (r.plays / cliffSize);
      uint256 markup = cliffs * incBps;
      if (markup > maxBps) markup = maxBps;
      return (r.basePrice * (10000 + markup)) / 10000;
    }
    revert("model");
  }

  function play(uint256 id, uint256 maxPrice) external nonReentrant {
    Round storage r = rounds[id];
    require(!r.finalized, "finalized");
    require(block.timestamp <= r.deadline, "ended");

    uint256 price = getCurrentPrice(id);
    require(price <= maxPrice, "slippage");

    IERC20 token = IERC20(r.token);
    uint256 beforeBal = token.balanceOf(address(this));
    token.safeTransferFrom(msg.sender, address(this), price);
    uint256 received = token.balanceOf(address(this)) - beforeBal;

    uint256 devAmt = (received * r.devFeeBps) / 10000;
    uint256 treasAmt = (received * r.treasuryFeeBps) / 10000;
    uint256 potAmt = received - devAmt - treasAmt;

    r.pot += potAmt;
    if (devAmt > 0) token.safeTransfer(r.dev, devAmt);
    if (treasAmt > 0) token.safeTransfer(r.treasury, treasAmt);

    r.plays += 1;
    r.currentWinner = msg.sender;
    r.deadline = uint64(block.timestamp + r.roundDuration);

    emit Play(id, msg.sender, received, r.pot, r.deadline);
  }

  function finalize(uint256 id) external nonReentrant {
    Round storage r = rounds[id];
    require(!r.finalized, "finalized");
    require(block.timestamp > r.deadline, "not ended");

    r.finalized = true;
    r.endTime = uint64(block.timestamp);

    address winner = r.currentWinner;
    uint256 potAmt = r.pot;

    IERC20(r.token).safeTransfer(winner, potAmt);

    emit RoundEnded(id, winner, r.endTime);
    emit Finalized(id, winner, potAmt, 0, 0);
  }

  function getTimeRemaining(uint256 id) external view returns (uint64) {
    Round storage r = rounds[id];
    if (block.timestamp >= r.deadline) return 0;
    return uint64(r.deadline - block.timestamp);
  }
}
