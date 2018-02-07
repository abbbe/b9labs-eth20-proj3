var RockPaperScissors = artifacts.require("./RockPaperScissors.sol");

contract('RockPaperScissors', function (accounts) {
  var rps;

  beforeEach("deploy new instance", function () {
    return RockPaperScissors.new()
      .then(_instance => rps = _instance);
  });

  it("should do something");
});
