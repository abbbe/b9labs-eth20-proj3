pragma solidity 0.4.18;

/*
 * 1. Someone initializes the contract, specifies bet amount and addresses of Alice and Bob.
 * 2. Alice and Bob call depositBetHash(), providing betHash and passing funds along.
 * 3. Alice and Bob call depositBetNonce(), revealing nonce they used to create betHash.
 * 4. Winner calls claim() to collect the reward.
 *
 * Bet hash is constructed from:
 * - contract address (to make sure there is some entropy uncontrolled by the player)
 * - bet value
 * - bet nonce
 *
 * Player must not try depositing bet & nonce until another player deposited their hash.
 * Player must not use nonce which results in zero hash (unlikely to happen anyway).
 *
 * If one player deposits hash/nonce and another does not, funds of the first player are frozen in the contract.
 * This can be solved by specifying a timeout after which the game gets canceled and players can withdraw their funds.
 */

contract RockPaperScissors {
  uint256 betAmount;
  address alice;
  address bob;

  // hash (if hash non-zero => hash&funds deposited by player)
  bytes32 aliceBetHash;
  bytes32 bobBetHash;

  // bet and nonce (if nonce is not-zero => bet&nonce deposided by player)
  enum RpsBet { Null, Rock, Paper, Scissors }
  RpsBet aliceBet;
  RpsBet bobBet;
  uint256 aliceBetNonce;
  uint256 bobBetNonce;

  uint256 aliceReward;
  uint256 bobReward;

  enum RpsOutcome { TIE, WON, LOST }

  event LogWaitingDepositHash(address indexed player, uint256 amount);
  event LogHashDeposited(address indexed player);
  event LogWaitingDepositBetNonce(address indexed player);
  event LogBetNonceDeposited(address indexed player);
  event LogOutcome(address indexed player, address otherPlayer, RpsBet yourBet, RpsBet otherBet, RpsOutcome outcome, uint256 yourReward);

  function RockPaperScissors(uint256 _betAmount, address _alice, address _bob) public {
    require(_alice != 0);
    require(_bob != 0);
    betAmount = _betAmount;
    alice = _alice;
    bob = _bob;

    LogWaitingDepositHash(alice, betAmount);
    LogWaitingDepositHash(bob, betAmount);
  }

  function depositBetHash(bytes32 betHash) public payable {
    require(msg.sender == alice || msg.sender == bob);
    require(msg.value == betAmount); // exact amount please, we don't have change, sorry

    if (msg.sender == alice) {
      require(aliceBetHash == 0); // do not accept hash deposit for 2nd time
      aliceBetHash = betHash;
      LogHashDeposited(alice);
    } else if (msg.sender == bob) {
      require(bobBetHash == 0); // do not accept hash deposit for 2nd time
      bobBetHash = betHash;
      LogHashDeposited(bob);
    }

    if (aliceBetHash != 0 && bobBetHash != 0) {
      LogWaitingDepositBetNonce(alice);
      LogWaitingDepositBetNonce(bob);
    }
  }

  function depositBetNonce(RpsBet bet, uint256 betNonce) public {
    // do not accept bet/nonce deposit until both players deposited their hashes
    require(aliceBetHash != 0);
    require(bobBetHash != 0);

    require(msg.sender == alice || msg.sender == bob);
    require(bet == RpsBet.Rock || bet == RpsBet.Paper || bet == RpsBet.Scissors);

    if (msg.sender == alice) {
      require(aliceBet == RpsBet.Null); // do not accept bet/nonce deposit for 2nd time
      bytes32 _aliceBetHash = keccak256(this, bet, betNonce);
      require(_aliceBetHash == aliceBetHash);
      aliceBet = bet;
      aliceBetNonce = betNonce;
      LogBetNonceDeposited(alice);
    } else if (msg.sender == bob) {
      require(bobBet == RpsBet.Null); // do not accept bet/nonce deposit for 2nd time
      bytes32 _bobBetHash = keccak256(this, bet, betNonce);
      require(_bobBetHash == bobBetHash);
      bobBet = bet;
      bobBetNonce = betNonce;
      LogBetNonceDeposited(bob);
    }

    if (aliceBet != RpsBet.Null && bobBet != RpsBet.Null) {
      calculateRewards();
    }
  }

  function calculateRewards() private {
    RpsOutcome aliceOutcome;
    RpsOutcome bobOutcome;

    // we have everything to figure out who won
    if (aliceBet == bobBet) {
      // tie
      aliceReward = betAmount;
      bobReward = betAmount;
      aliceOutcome = RpsOutcome.TIE;
      bobOutcome = RpsOutcome.TIE;
    } else {
      bool aliceWon = true;
      if (aliceBet == RpsBet.Rock && bobBet == RpsBet.Paper) {
        aliceWon = false;
      } else if (aliceBet == RpsBet.Scissors && bobBet == RpsBet.Rock) {
        aliceWon = false;
      } else if (aliceBet == RpsBet.Paper && bobBet == RpsBet.Scissors) {
        aliceWon = false;
      } // else - Alice won

      if (aliceWon) {
        aliceOutcome = RpsOutcome.WON;
        bobOutcome = RpsOutcome.LOST;
        aliceReward = 2 * betAmount;
        bobReward = 0;
      } else {
        aliceOutcome = RpsOutcome.LOST;
        bobOutcome = RpsOutcome.WON;
        aliceReward = 0;
        bobReward = 2 * betAmount;
      }
    }

    LogOutcome(alice, bob, aliceBet, bobBet, aliceOutcome, aliceReward);
    LogOutcome(bob, alice, bobBet, aliceBet, bobOutcome, bobReward);
  }

  function claim() public {
    if (msg.sender == alice) {
      require(aliceReward > 0);
      uint256 _aliceReward = aliceReward;
      aliceReward = 0;
      alice.transfer(_aliceReward);
    } else if (msg.sender == bob) {
      require(bobReward > 0);
      uint256 _bobReward = bobReward;
      bobReward = 0;
      bob.transfer(_bobReward);
    } else {
      revert();
    }
  }
}
