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
  const aliceBet = RpsBet.Rock;
  const aliceBetNonce = "0x1111111111111111111111111111111111111111111111111111111111111111";
  const bobBet = RpsBet.Paper;
  const bobBetNonce = "0x2222222222222222222222222222222222222222222222222222222222222222";
  const bobBet2 = RpsBet.Scissors;
  const bobBetNonce2 = "0x3333333333333333333333333333333333333333333333333333333333333333";
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
    // console.log("**** redeployed ***")
    return RockPaperScissors.new()
      .then(_instance => rps = _instance);
  });

  it("should do rewards calculation right");

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
    let aliceBetHash, bobBetHash, bobBetHash2;

    beforeEach("reset the hashes", function () {
      // console.log("**** reset the hashes ***")
      return rps.hashThat(aliceBet, aliceBetNonce)
        .then(_aliceBetHash => aliceBetHash = _aliceBetHash)
        .then(() => rps.hashThat(bobBet, bobBetNonce))
        .then(_bobBetHash => bobBetHash = _bobBetHash)
        .then(() => rps.hashThat(bobBet2, bobBetNonce2))
        .then(_bobBetHash2 => bobBetHash2 = _bobBetHash2);
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
          assert.isAtLeast(txObject.receipt.gasUsed, "86000");
          assert.isAtMost(txObject.receipt.gasUsed, "88000");
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
        .then(() => rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1001, gas: 3000000 }))
        .then(txObject => rps.games(aliceBetHash)
          .then(([sender, amount, lastMatchBlock]) => {
            assert.strictEqual(sender, alice);
            assert.strictEqual(amount.toString(10), "1001");
            // FIXME assert.strictEqual(lastMatchBlock.toString(10), "0");
            assert.strictEqual(
              lastMatchBlock.toString(10),
              web3.toBigNumber(172800).plus(txObject.receipt.blockNumber).toString(10));
          })
        );
    });

    describe("again", function () {

      beforeEach("new from bob", function () {
        // console.log("**** newChallenge - bob ***")
        return rps.newChallenge(bobBetHash, 172800, { from: bob, value: 1001, gas: 3000000 });
      });

      it("should reject existing hash with same parameters", function () {
        return expectedException(
          () => rps.newChallenge(bobBetHash, 172800, { from: bob, value: 1001, gas: 3000000 }),
          3000000);
      });

      it("should reject existing hash with different timeout", function () {
        return expectedException(
          () => rps.newChallenge(bobBetHash, 172799, { from: bob, value: 1001, gas: 3000000 }),
          3000000);
      });

      it("should reject existing hash with different bob", function () {
        return expectedException(
          () => rps.newChallenge(bobBetHash, 172800, { from: carol, value: 1001, gas: 3000000 }),
          3000000);
      });

      it("should emit a single event on second challenge with different hash", function () {
        return rps.newChallenge(bobBetHash2, 172800, { from: alice, value: 1001, gas: 3000000 })
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

      it("should keep Weis in contract on second deposit with different hash", function () {
        return rps.newChallenge(bobBetHash2, 172800, { from: bob, value: 2002, gas: 3000000 })
          .then(txObject => web3.eth.getBalancePromise(rps.address))
          .then(balance => assert.strictEqual(balance.toString(10), "3003"));
      });

      it("should update games[] on second deposit with different hash", function () {
        return rps.games(bobBetHash2)
          .then(([sender, amount, lastMatchBlock]) => {
            assert.strictEqual(sender, address0);
            assert.strictEqual(amount.toString(10), "0");
            assert.strictEqual(lastMatchBlock.toString(10), "0");
          })
          .then(() => rps.newChallenge(bobBetHash2, 172800, { from: bob, value: 1001, gas: 3000000 })
            .then(txObject => rps.games(bobBetHash2)
              .then(([sender, amount, lastMatchBlock]) => {
                assert.strictEqual(sender, bob);
                assert.strictEqual(amount.toString(10), "1001");
                // FIXME assert.strictEqual(lastMatchBlock.toString(10), "0");
                assert.strictEqual(
                  lastMatchBlock.toString(10),
                  web3.toBigNumber(172800).plus(txObject.receipt.blockNumber).toString(10));
              })
            ));
      });

      it("should reject withdrawal before timeout");
      it("should allow withdrawal after timeout");
    });

    describe("accept challenge", function () {
      beforeEach("new from alice", function () {
        // console.log("**** newChallenge - alice ***")
        return rps.newChallenge(aliceBetHash, 172800, { from: alice, value: 1234, gas: 3000000 });
      });

      it("should reject mismatched amount", function () {
        return expectedException(
          () => rps.acceptChallenge(aliceBetHash, bobBetHash, { from: bob, value: 4321 }),
          3000000);
      });

      it("should reject alice even with matching amount", function () {
        return expectedException(
          () => rps.acceptChallenge(aliceBetHash, bobBetHash, { from: alice, value: 1234 }),
          3000000);
      });

      it("should accept matched amount", function () {
        return rps.acceptChallenge(aliceBetHash, bobBetHash, { from: bob, value: 1234 });
      });

      describe("deposit bet/nonce", function () {
        beforeEach("accept from bob", function () {
          // console.log("**** acceptChallenge - bob ***")
          return rps.acceptChallenge(aliceBetHash, bobBetHash, { from: bob, value: 1234 });
        });

        it("should reject valid bet/nonce from other people", function () {
          return expectedException(
            () => rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: carol }),
            3000000);
        });

        it("should reject invalid bet/nonce", function () {
          return expectedException(
            () => rps.depositBetNonce(aliceBetHash, bobBet2, bobBetNonce, { from: bob }),
            3000000);
        });

        it("should accept valid bet/nonce from alice", function () {
          return rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: alice });
        });

        it("should emit a single event on accepting valid bet/nonce from alice", function () {
          return rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: alice }).then(txObject => {
            assert.strictEqual(txObject.logs.length, 1);
            assert.strictEqual(txObject.logs[0].event, "LogBetNonce");
            assert.strictEqual(txObject.logs[0].args.aliceBetHash, aliceBetHash, 'hash mismatch');
            assert.strictEqual(txObject.logs[0].args.player, alice, 'player address mismatch');
            assert.strictEqual(txObject.logs[0].args.bet.toString(), aliceBet.toString(), 'bet mismatch');
            assert.strictEqual(txObject.logs[0].args.betNonce, aliceBetNonce, 'nonce mismatch');
          });
        });

        it("should reject bet/nonce from alice 2nd time", function () {
          return rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: alice })
            .then(() => expectedException(
              () => rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: alice })
            ));
        });

        it("should accept valid bet/nonce from bob", function () {
          return rps.depositBetNonce(aliceBetHash, bobBet, bobBetNonce, { from: bob });
        });

        it("should emit a single event on accepting valid bet/nonce from bob", function () {
          return rps.depositBetNonce(aliceBetHash, bobBet, bobBetNonce, { from: bob }).then(txObject => {
            assert.strictEqual(txObject.logs.length, 1);
            assert.strictEqual(txObject.logs[0].event, "LogBetNonce");
            assert.strictEqual(txObject.logs[0].args.aliceBetHash, aliceBetHash, 'hash mismatch');
            assert.strictEqual(txObject.logs[0].args.player, bob, 'player address mismatch');
            assert.strictEqual(txObject.logs[0].args.bet.toString(), bobBet.toString(), 'bet mismatch');
            assert.strictEqual(txObject.logs[0].args.betNonce, bobBetNonce, 'nonce mismatch');
          });
        });

        it("should emit additional event if both players submitted valid bet/nonce", function () {
          return rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: alice })
            .then(() => rps.depositBetNonce(aliceBetHash, bobBet, bobBetNonce, { from: bob }))
            .then(txObject => {
              assert.strictEqual(txObject.logs.length, 2);
              assert.strictEqual(txObject.logs[0].event, "LogBetNonce");
              assert.strictEqual(txObject.logs[0].args.aliceBetHash, aliceBetHash, 'hash mismatch');
              assert.strictEqual(txObject.logs[0].args.player, bob, 'player address mismatch');
              assert.strictEqual(txObject.logs[0].args.bet.toString(), bobBet.toString(), 'bet mismatch');
              assert.strictEqual(txObject.logs[0].args.betNonce, bobBetNonce, 'nonce mismatch');
              assert.strictEqual(txObject.logs[1].event, "LogRewards");
              assert.strictEqual(txObject.logs[1].args.aliceBetHash, aliceBetHash, 'hash mismatch');
              assert.strictEqual(txObject.logs[1].args.aliceReward.toString(10), '0', 'aliceReward mismatch');
              assert.strictEqual(txObject.logs[1].args.bobReward.toString(10), '2468', 'bobReward mismatch');
            });
        });

        it("should reject bet/nonce from bob 2nd time", function () {
          return rps.depositBetNonce(aliceBetHash, bobBet, bobBetNonce, { from: bob })
            .then(() => expectedException(
              () => rps.depositBetNonce(aliceBetHash, bobBet, bobBetNonce, { from: bob, gas: 3000000 }),
              3000000));
        });

        it("should reject withdrawal before timeout");

        it("should allow withdrawal after timeout");

        describe("reward", function () {
          beforeEach("accept from bob", function () {
            // console.log("**** depositBetNonce - alice ***");
            // console.log("**** depositBetNonce - bob ***");
            return rps.depositBetNonce(aliceBetHash, aliceBet, aliceBetNonce, { from: alice })
              .then(() => rps.depositBetNonce(aliceBetHash, bobBet, bobBetNonce, { from: bob }));
          });

          it("should reject claim from carol - 3rd party", function () {
            return expectedException(
              () => rps.claim(aliceBetHash, { from: carol }),
              3000000);
          });

          it("should reject claim from alice - the looser", function () {
            return expectedException(
              () => rps.claim(aliceBetHash, { from: alice }),
              3000000);
          });

          it("should transfer reward by demand of bob - the winner", function () {
            let balance0;
            return web3.eth.getBalancePromise(rps.address)
              .then(_balance => {
                balance0 = _balance;
                return rps.claim(aliceBetHash, { from: bob });
              })
              .then(txObject => web3.eth.getBalancePromise(rps.address))
              .then(balance => assert.strictEqual(balance.minus(balance0).toString(10), "-2468"));
          });

          it("should emit a single event on bob's claim", function () {
            return rps.claim(aliceBetHash, { from: bob })
              .then(txObject => {
                assert.strictEqual(txObject.logs.length, 1);
                assert.strictEqual(txObject.logs[0].event, "LogClaim");
                assert.strictEqual(txObject.logs[0].args.aliceBetHash, aliceBetHash, 'hash mismatch');
                assert.strictEqual(txObject.logs[0].args.player, bob, 'player address mismatch');
                assert.strictEqual(txObject.logs[0].args.amount.toString(), '2468', 'amount mismatch');
              });
          });

          it("should reject 2nd claim from bob", function () {
            return rps.claim(aliceBetHash, { from: bob })
              .then(() => expectedException(
                () => rps.claim(aliceBetHash, { from: bob }),
                3000000));
          });
        });
      });
    });
  })
});
