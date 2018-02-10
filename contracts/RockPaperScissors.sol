pragma solidity ^0.4.18;

/*
 * 1. Alice calls newChallenge(), providing betHash, timeout, and sending funds
 * 2. Bob sees Alice's challenge, calls matchBetHash(), providing his betHash, and sending funds
 * 3. Alice and Bob call depositBetNonce(), revealing bet and nonce they used to create betHash.
 * 4. Alice and Bob call claim() to collect the reward.
 * 5. Alice can claim() if nobody has not matched before timeout.
 * 6. Either party can claim() if another party has not deposited bet&nonce before timeout (counted anew from their bet&nonce deposit)
 *
 * All calls above (except 1st) use aliceBetHash argument to refer to the game
 *
 * Bet hash is constructed from:
 * - contract address (to make sure there is some entropy uncontrolled by the player)
 * - bet value
 * - bet nonce
 *
 * Player must not try depositing bet & nonce until another player deposited their hash.
 * Player must not use nonce which results in zero hash (unlikely to happen anyway).
 * Player must not reuse nonce (or opponent can recover bet from results of an old game).
 *
 */

contract RockPaperScissors {
  uint constant ONE_DAY_OF_BLOCKS = 86400 / 15;         // 5,760
  uint constant ONE_YEAR_OF_BLOCKS = 30 * 86400 / 15;   // 172,800

  enum RpsBet { Null, Rock, Paper, Scissors }

  struct Game {
    address alice;
    uint amount;
    uint lastMatchBlock;
    address bob;
    bytes32 bobBetHash;
  }

  mapping (bytes32 => Game) public games;

  event LogChallenge(address indexed alice, bytes32 indexed aliceBetHash, uint amount, uint lastMatchBlock);
  event LogChallengeAccepted(bytes32 indexed aliceBetHash, address indexed bob, bytes32 bobBetHash);

  function hashThat(bytes32 bet, bytes32 betNonce)
    pure public
    returns(bytes32 hash)
  {
    return keccak256(bet, betNonce);
  }

  function newChallenge(bytes32 betHash, uint timeout) public payable {
    require(msg.value > 0);
    require(timeout >= ONE_DAY_OF_BLOCKS);
    require(timeout <= ONE_YEAR_OF_BLOCKS);

    Game storage game = games[betHash];
    require(game.alice == 0);

    uint lastMatchBlock = block.number + timeout;
    game.alice = msg.sender;
    game.amount = msg.value;
    game.lastMatchBlock = lastMatchBlock;

    LogChallenge(msg.sender, betHash, msg.value, lastMatchBlock);
  }

  function acceptChallenge(bytes32 aliceBetHash, bytes32 bobBetHash) public payable {
    Game storage game = games[aliceBetHash];
    require(msg.sender != game.alice); // can't play with yourself
    require(msg.value == game.amount); // exact amount please, we don't have change, sorry
    require(game.bob == 0); // can't accept challenge which was accepted already

    game.bob = msg.sender;
    game.bobBetHash = bobBetHash;
    LogChallengeAccepted(aliceBetHash, msg.sender, bobBetHash);
  }

  // // bet and nonce (if nonce is not-zero => bet&nonce deposided by player)
  // RpsBet aliceBet;
  // RpsBet bobBet;
  // uint256 aliceBetNonce;
  // uint256 bobBetNonce;

  // uint256 aliceReward;
  // uint256 bobReward;

  // enum RpsOutcome { TIE, WON, LOST }

  // event LogWaitingDepositHash(address indexed player, uint256 amount);
  // event LogHashDeposited(address indexed player);
  // event LogWaitingDepositBetNonce(address indexed player);
  // event LogBetNonceDeposited(address indexed player);
  // event LogOutcome(address indexed player, address otherPlayer, RpsBet yourBet, RpsBet otherBet, RpsOutcome outcome, uint256 yourReward);
  // // + event LogClaim

  // function RockPaperScissors(uint256 _betAmount, address _alice, address _bob) public {
  //   require(_alice != 0);
  //   require(_bob != 0);
  //   betAmount = _betAmount;
  //   alice = _alice;
  //   bob = _bob;

  //   LogWaitingDepositHash(alice, betAmount);
  //   LogWaitingDepositHash(bob, betAmount);
  // }

  // function depositBetHash(bytes32 betHash) public payable {
  //   require(msg.sender == alice || msg.sender == bob);
  //   require(msg.value == betAmount); // exact amount please, we don't have change, sorry

  //   if (msg.sender == alice) {
  //     require(aliceBetHash == 0); // do not accept hash deposit for 2nd time
  //     aliceBetHash = betHash;
  //     LogHashDeposited(alice);
  //   } else if (msg.sender == bob) {
  //     require(bobBetHash == 0); // do not accept hash deposit for 2nd time
  //     bobBetHash = betHash;
  //     LogHashDeposited(bob);
  //   }

  //   if (aliceBetHash != 0 && bobBetHash != 0) {
  //     LogWaitingDepositBetNonce(alice);
  //     LogWaitingDepositBetNonce(bob);
  //   }
  // }

  // function depositBetNonce(RpsBet bet, uint256 betNonce) public {
  //   // do not accept bet/nonce deposit until both players deposited their hashes
  //   require(aliceBetHash != 0);
  //   require(bobBetHash != 0);

  //   require(msg.sender == alice || msg.sender == bob);
  //   require(bet == RpsBet.Rock || bet == RpsBet.Paper || bet == RpsBet.Scissors);

  //   if (msg.sender == alice) {
  //     require(aliceBet == RpsBet.Null); // do not accept bet/nonce deposit for 2nd time
  //     bytes32 _aliceBetHash = keccak256(this, bet, betNonce);
  //     require(_aliceBetHash == aliceBetHash);
  //     aliceBet = bet;
  //     aliceBetNonce = betNonce;
  //     LogBetNonceDeposited(alice);
  //   } else {
  //     require(bobBet == RpsBet.Null); // do not accept bet/nonce deposit for 2nd time
  //     bytes32 _bobBetHash = keccak256(this, bet, betNonce);
  //     require(_bobBetHash == bobBetHash);
  //     bobBet = bet;
  //     bobBetNonce = betNonce;
  //     LogBetNonceDeposited(bob);
  //   }

  //   if (aliceBet != RpsBet.Null && bobBet != RpsBet.Null) {
  //     calculateRewards();
  //   }
  // }

  // function calculateRewards() private {
  //   RpsOutcome aliceOutcome;
  //   RpsOutcome bobOutcome;

  //   // we have everything to figure out who won
  //   if (aliceBet == bobBet) {
  //     // tie
  //     aliceReward = betAmount;
  //     bobReward = betAmount;
  //     aliceOutcome = RpsOutcome.TIE;
  //     bobOutcome = RpsOutcome.TIE;
  //   } else {
  //     bool aliceWon = true;
  //     if (aliceBet == RpsBet.Rock && bobBet == RpsBet.Paper) {
  //       aliceWon = false;
  //     } else if (aliceBet == RpsBet.Scissors && bobBet == RpsBet.Rock) {
  //       aliceWon = false;
  //     } else if (aliceBet == RpsBet.Paper && bobBet == RpsBet.Scissors) {
  //       aliceWon = false;
  //     } // else - Alice won

  //     if (aliceWon) {
  //       aliceOutcome = RpsOutcome.WON;
  //       bobOutcome = RpsOutcome.LOST;
  //       aliceReward = 2 * betAmount;
  //       bobReward = 0;
  //     } else {
  //       aliceOutcome = RpsOutcome.LOST;
  //       bobOutcome = RpsOutcome.WON;
  //       aliceReward = 0;
  //       bobReward = 2 * betAmount;
  //     }
  //   }

  //   LogOutcome(alice, bob, aliceBet, bobBet, aliceOutcome, aliceReward);
  //   LogOutcome(bob, alice, bobBet, aliceBet, bobOutcome, bobReward);
  // }

  // function claim() public {
  //   if (msg.sender == alice) {
  //     require(aliceReward > 0);
  //     uint256 _aliceReward = aliceReward;
  //     aliceReward = 0;
  //     alice.transfer(_aliceReward);
  //     // + LogClaim
  //   } else if (msg.sender == bob) {
  //     require(bobReward > 0);
  //     uint256 _bobReward = bobReward;
  //     bobReward = 0;
  //     bob.transfer(_bobReward);
  //     // + LogClaim
  //   } else {
  //     revert();
  //   }
  // }
}
