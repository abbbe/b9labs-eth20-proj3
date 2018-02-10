Promise = require("bluebird");

const expectedException = require("../utils/expectedException.js");
// const sequentialPromise = require("../utils/sequentialPromise.js");
web3.eth.makeSureHasAtLeast = require("../utils/makeSureHasAtLeast.js");
web3.eth.makeSureAreUnlocked = require("../utils/makeSureAreUnlocked.js");
web3.eth.getTransactionReceiptMined = require("../utils/getTransactionReceiptMined.js");

if (typeof web3.eth.getBlockPromise !== "function") {
  Promise.promisifyAll(web3.eth, { suffix: "Promise" });
}

var RockPaperScissors = artifacts.require("./RockPaperScissors.sol");
var RpsBet = Object.freeze({ "Null": 0, "Rock": 1, "Paper": 2, "Scissors": 3 })

contract('RockPaperScissors', function (accounts) {
  const aliceBet = RpsBet.Rock; // , bet2 = RpsBet.Paper, bet3 = RpsBet.Scissors;
  const aliceBetNonce = "0x1111111111111111111111111111111111111111";
  // const nonce2 = "0x2222222222222222222222222222222222222222";
  // const nonce3 = "0x3333333333333333333333333333333333333333";
  const address0 = "0x0000000000000000000000000000000000000000";
  let rps, alice, bob, carol;

  before("should prepare accounts", function () {
    let coinbase;
    assert.isAtLeast(accounts.length, 4, "should have at least 4 accounts");
    [coinbase, alice, bob, carol] = accounts;
    return web3.eth.makeSureAreUnlocked([alice, bob, carol])
      .then(() => web3.eth.makeSureHasAtLeast(coinbase, [alice, bob, carol], web3.toWei(10)))
      .then(txHashes => web3.eth.getTransactionReceiptMined(txHashes))
  });

  beforeEach("deploy new RockPaperScissors", function () {
    return RockPaperScissors.new()
      .then(_instance => rps = _instance);
  });

  it("should reject direct transaction with value", function () {
    return expectedException(
      () => rps.sendTransaction({ from: alice, value: 1, gas: 3000000 }),
      3000000);
  });

  it("should reject direct transaction without value", function () {
    return expectedException(
      () => rps.sendTransaction({ from: alice, gas: 3000000 }),
      3000000);
  });

  describe("new challenge", function () {
    let aliceBetHash;

    beforeEach("reset the hashes", function () {
      return rps.hashThat(aliceBet, aliceBetNonce)
        .then(_aliceBetHash => aliceBetHash = _aliceBetHash);
    });

    it("should reject with 1 day minus 1 block timeout", function () {
      return expectedException(
        () => rps.newChallenge(aliceBetHash, 5759, { from: alice, value: 1, gas: 3000000 }),
        3000000);
    });

    it("should accept with 1 day timeout", function () {
      return rps.newChallenge(aliceBetHash, 5760, { from: alice, value: 1, gas: 3000000 });
    });

    it("should accept with exactly 30 days of timeout", function () {
      return rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1, gas: 3000000 });
    });

    it("should reject with 30 days and 1 block of duration", function () {
      return expectedException(
        () => rps.newChallenge(aliceBetHash, 172801, { from: alice, value: 1, gas: 3000000 }),
        3000000);
    });

    it("should emit a single event", function () {
      return rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1001, gas: 3000000 })
        .then(txObject => {
          assert.strictEqual(txObject.logs.length, 1);
          assert.strictEqual(txObject.logs[0].event, "LogChallenge");
          assert.strictEqual(txObject.logs[0].args.alice, alice);
          assert.strictEqual(txObject.logs[0].args.amount.toString(10), "1001");
          assert.strictEqual(
            txObject.logs[0].args.lastMatchBlock.toString(10),
            web3.toBigNumber(172800).plus(txObject.receipt.blockNumber).toString(10));
        });
    });

    it("should consume 86k gas", function () {
      return rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1, gas: 3000000 })
        .then(txObject => {
          assert.isAtLeast(txObject.receipt.gasUsed, "86700");
          assert.isAtMost(txObject.receipt.gasUsed, "86900");
        });
    });

    it("should keep Weis in contract", function () {
      return rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1001, gas: 3000000 })
        .then(txObject => web3.eth.getBalancePromise(rps.address))
        .then(balance => assert.strictEqual(balance.toString(10), "1001"));
    });

    it("should update games[]", function () {
      return rps.games(aliceBetHash)
        .then(([sender, amount, lastMatchBlock]) => {
          assert.strictEqual(sender, address0);
          assert.strictEqual(amount.toString(10), "0");
          assert.strictEqual(lastMatchBlock.toString(10), "0");
        })
        .then(() => rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1001, gas: 3000000 })
          .then(txObject => rps.games(aliceBetHash)
            .then(([sender, amount, lastMatchBlock]) => {
              assert.strictEqual(sender, alice);
              assert.strictEqual(amount.toString(10), "1001");
              // assert.strictEqual(lastMatchBlock.toString(10), "0");
              assert.strictEqual(
                lastMatchBlock.toString(10),
                web3.toBigNumber(172800).plus(txObject.receipt.blockNumber).toString(10));
            })
          ));
    });
  })
});
