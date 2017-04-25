pragma solidity ^0.4.6;

import "./ERC20.sol";
import "./SafeMath.sol";

contract OpenCollabToken is ERC20, SafeMath {
  string public standard = "ERC20";
  string public name = "OpenCollabToken";
  string public symbol = "OCT";

  address public repoAddress;
  address owner;

  mapping (address => uint) balances;
  mapping (address => mapping (address => uint256)) allowed;

  function OpenCollabToken(address _repoAddress) {
    repoAddress = _repoAddress;
    owner = msg.sender;
  }

  function mint(uint value) {
    // For testing purposes only
    if (msg.sender != owner) throw;

    totalSupply = value;
    balances[owner] = value;
  }

  // ERC20 standard functions

  function transfer(address to, uint256 value) returns (bool success) {
    balances[msg.sender] = safeSub(balances[msg.sender], value);
    balances[to] = safeAdd(balances[to], value);

    Transfer(msg.sender, to, value);

    return true;
  }

  function transferFrom(address from, address to, uint value) returns (bool success) {
    var allowance = allowed[from][msg.sender];

    balances[to] = safeAdd(balances[to], value);
    balances[from] = safeSub(balances[from], value);
    allowed[from][msg.sender] = safeSub(allowance, value); // safeSub throws if value > allowance, rolling everything back

    Transfer(from, to, value);

    return true;
  }

  function balanceOf(address owner) constant returns (uint balance) {
    return balances[owner];
  }

  function approve(address spender, uint value) returns (bool success) {
    allowed[msg.sender][spender] = value;

    Approval(msg.sender, spender, value);

    return true;
  }

  function allowance(address owner, address spender) constant returns (uint remaining) {
    return allowed[owner][spender];
  }
}
