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
  uint constant ONE_DAY = 86400;
  uint constant ONE_WEEK = 7 * 86400;
  uint constant ONE_YEAR = 365 * 86400;

  enum RpsBet { Null, Rock, Paper, Scissors }

  struct Game {
    address alice;
    uint amount; // bet amount per player
    uint deadline; // set on newChallenge(), reset to now + 1 week on acceptChallenge(), zeroed after rewards are assigned
    address bob;
    bytes32 bobBetHash;
    RpsBet aliceBet;
    RpsBet bobBet;
    uint256 aliceReward;
    uint256 bobReward;
  }

  mapping (bytes32 => Game) public games;

  event LogChallenge(address indexed alice, bytes32 indexed aliceBetHash, uint amount, uint deadline);
  event LogChallengeAccepted(bytes32 indexed aliceBetHash, address indexed bob, bytes32 bobBetHash);
  event LogBetNonce(bytes32 indexed aliceBetHash, address player, RpsBet bet, bytes32 betNonce);
  event LogRewards(bytes32 indexed aliceBetHash, uint256 aliceReward, uint256 bobReward);
  event LogClaim(bytes32 indexed aliceBetHash, address player, uint256 amount);
  event LogWithdraw(bytes32 indexed aliceBetHash, address player, uint256 amount);

  function hashThat(RpsBet bet, bytes32 betNonce)
    pure public
    returns(bytes32 hash)
  {
    return keccak256(bet, betNonce);
  }

  /*
   * Alice calls newChallenge() to start the game. Bob is expected to take it by calling acceptChallenge().
   *   - betHash    = Alice's hash, serves as game ID for other methods.
   *   - timeout    = Time (in blocks) Bob has accept Alice's challenge.
   *   - msg.value  = Amount to bet. Bob must match it when calling acceptChallenge().
   */
  function newChallenge(bytes32 betHash, uint timeout) external payable {
    require(msg.value > 0);
    require(timeout >= ONE_DAY);
    require(timeout <= ONE_YEAR);

    Game storage game = games[betHash];
    require(game.alice == 0);

    uint deadline = block.timestamp + timeout;
    game.alice = msg.sender;
    game.amount = msg.value;
    game.deadline = deadline;

    LogChallenge(msg.sender, betHash, msg.value, deadline);
  }

  /*
   * Bob calls acceptChallenge() to accept Alice's game.
   *   - aliceBetHash  = hash of Alice's game
   *   - bobBetHash    = Bob's hash
   */
  function acceptChallenge(bytes32 aliceBetHash, bytes32 bobBetHash) external payable {
    Game storage game = games[aliceBetHash];
    require(msg.sender != game.alice); // can't play with yourself
    require(msg.value == game.amount); // exact amount please, we don't have change, sorry
    require(game.bob == 0); // can't accept challenge which was accepted already
    require(block.timestamp <= game.deadline); // check challenge has not expired

    game.bob = msg.sender;
    game.bobBetHash = bobBetHash;
    game.deadline = block.timestamp + ONE_WEEK;
    LogChallengeAccepted(aliceBetHash, msg.sender, bobBetHash);
  }

  /*
   * Alice and Bob call depositBetNonce() to deposit their bets and nonces.
   * After one player calls this method, another player must do the same before timeout or loose.
   */
  function depositBetNonce(bytes32 aliceBetHash, RpsBet bet, bytes32 betNonce) external {
    Game storage game = games[aliceBetHash];

    require(block.timestamp <= game.deadline); // check challenge has not expired

    // do not accept bet/nonce deposit until both players submitted their hashes
    require(game.bobBetHash != 0);

    // only accept bet/nonce from alice and bob
    require(msg.sender == game.alice || msg.sender == game.bob);

    // make sure valid bet value
    require(bet == RpsBet.Rock || bet == RpsBet.Paper || bet == RpsBet.Scissors);

    // calculate hash
    bytes32 _betHash = hashThat(bet, betNonce);

    if (msg.sender == game.alice) {
      require(game.aliceBet == RpsBet.Null); // do not accept bet/nonce deposit for 2nd time
      require(aliceBetHash == _betHash); // hash must match
      game.aliceBet = bet;
      LogBetNonce(aliceBetHash, msg.sender, bet, betNonce);
    } else {
      require(game.bobBet == RpsBet.Null); // do not accept bet/nonce deposit for 2nd time
      require(game.bobBetHash == _betHash); // hash must match
      game.bobBet = bet;
      LogBetNonce(aliceBetHash, msg.sender, bet, betNonce);
    }

    // use in-memory copy for bet values
    RpsBet aliceBet = game.aliceBet;
    RpsBet bobBet = game.bobBet;
    if (aliceBet == RpsBet.Null || bobBet == RpsBet.Null) {
      return;
    }

    // we have everything to figure out who has won
    uint256 aliceReward;
    uint256 bobReward;
    if (aliceBet == bobBet) {
      // tie
      aliceReward = bobReward = game.amount;
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
        aliceReward = 2 * game.amount;
      } else {
        bobReward = 2 * game.amount;
      }
    }

    game.aliceReward = aliceReward;
    game.bobReward = bobReward;
    game.deadline = 0;
    LogRewards(aliceBetHash, aliceReward, bobReward);
  }

  /*
   * Players must call claim() to get their reward.
   */
  function claim(bytes32 aliceBetHash) external {
    Game storage game = games[aliceBetHash];

    if (block.timestamp > game.deadline && game.deadline != 0) {
      // deadline has passed, one or both bets were not revealed (otherwise .deadline would be zeroed)
      game.deadline = 0;

      if (game.bob == 0) {
        // challenge has expired, bob has not accepted, let alice withdraw her funds
        game.aliceReward = game.amount;
      } else if (game.aliceBet != RpsBet.Null && game.bobBet == RpsBet.Null) {
        // bob has failed to reveal his bet, let alice withdraw everything
        game.aliceReward = 2 * game.amount;
      } else if (game.bobBet != RpsBet.Null && game.aliceBet == RpsBet.Null) {
        // alice has failed to revel her bet, let bob withdraw everything
        game.bobReward = 2 * game.amount;
      } else if (game.aliceBet == RpsBet.Null && game.bobBet == RpsBet.Null) {
        // both players have failed to reveal their bets, let both withdraw their funds
        game.aliceReward = game.bobReward = game.amount;
      } else {
        assert(false); // should never happen
      }
    }

    // by now players' rewards are settled

    uint256 reward;
    if (msg.sender == game.alice) {
      reward = game.aliceReward;
      require(reward > 0);
      game.aliceReward = 0;
    } else if (msg.sender == game.bob) {
      reward = game.bobReward;
      require(reward > 0);
      game.bobReward = 0;
    } else {
      revert();
    }

    LogClaim(aliceBetHash, msg.sender, reward);
    msg.sender.transfer(reward);
  }
}
