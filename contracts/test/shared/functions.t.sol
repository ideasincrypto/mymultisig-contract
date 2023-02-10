// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'foundry-test-utility/contracts/utils/console.sol';
import { CheatCodes } from 'foundry-test-utility/contracts/utils/cheatcodes.sol';
import { Signatures } from 'foundry-test-utility/contracts/shared/signatures.sol';
import { Constants } from './constants.t.sol';
import { Errors } from './errors.t.sol';

import { MyMultiSigFactory } from '../../MyMultiSigFactory.sol';
import { MyMultiSig } from '../../MyMultiSig.sol';

contract Functions is Constants, Signatures {
  uint8 LOG_LEVEL;
  uint256 DEFAULT_BLOCKS_COUNT;

  MyMultiSigFactory public myMultiSigFactory;
  MyMultiSig public myMultiSig;

  enum TestType {
    TestWithFactory,
    TestWithoutFactory
  }

  // MyMultiSigFactory
  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners
  );

  // MyMultiSig
  event OwnerAdded(address indexed owner);
  event OwnerRemoved(address indexed owner);
  event ThresholdChanged(uint256 indexed threshold);
  event TransactionExecuted(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce
  );
  event TransactionFailed(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce
  );
  event ContractEndOfLife(uint256 indexed txNonceLefts);

  function initialize_tests(uint8 LOG_LEVEL_, TestType testType_) public returns (MyMultiSigFactory, MyMultiSig) {
    // Set general test settings
    LOG_LEVEL = LOG_LEVEL_;
    vm.roll(1);
    vm.warp(100);
    vm.prank(ADMIN);

    if (testType_ == TestType.TestWithFactory) {
      myMultiSigFactory = new MyMultiSigFactory();
      (, myMultiSig) = help_createMultiSig(ADMIN, CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    } else {
      myMultiSig = new MyMultiSig(CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    }

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 100);

    return (myMultiSigFactory, myMultiSig);
  }

  // MyMultiSigFactory
  function help_createMultiSig(
    address prank_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    Errors.RevertStatus revertType_
  ) internal returns (uint256 multiSigId, MyMultiSig newMultiSig) {
    vm.prank(prank_);
    verify_revertCall(revertType_);
    myMultiSigFactory.createMultiSig(contractName_, owners_, threshold_);

    if (revertType_ == Errors.RevertStatus.Success) {
      multiSigId = myMultiSigFactory.multiSigCount();
      newMultiSig = MyMultiSig(myMultiSigFactory.multiSig(multiSigId - 1));
      assertEq(newMultiSig.name(), contractName_);
      assertEq(newMultiSig.threshold(), threshold_);
      uint256 ownersLength = owners_.length;
      assertEq(newMultiSig.ownerCount(), ownersLength);
      for (uint256 i = 0; i < ownersLength; i++) {
        assertTrue(newMultiSig.isOwner(owners_[i]));
      }
    }
  }

  function help_createMultiSig(
    address prank_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) internal returns (uint256 multiSigId, MyMultiSig newMultiSig) {
    return help_createMultiSig(prank_, contractName_, owners_, threshold_, Errors.RevertStatus.Success);
  }

  // MyMultiSigFactory
  function build_domainSeparator(MyMultiSig multiSig_, string memory contractName_) public returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
          bytes32(keccak256(bytes(contractName_))),
          bytes32(keccak256(bytes(CONTRACT_VERSION))),
          block.chainid,
          address(multiSig_)
        )
      );
  }

  function build_signatures(
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_
  ) public returns (bytes memory signatures) {
    uint256 nonce = multiSig_.nonce();
    bytes32 domainSeparator = build_domainSeparator(multiSig_, multiSig_.name());
    for (uint256 i = 0; i < ownersPk_.length; i++) {
      signatures = abi.encodePacked(
        signatures,
        signature_signHashed(
          ownersPk_[i],
          domainSeparator,
          keccak256(
            abi.encode(
              keccak256('Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce)'),
              to_,
              value_,
              keccak256(data_),
              txnGas_,
              nonce
            )
          )
        )
      );
    }
  }

  function build_multiRequest(
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_
  ) internal pure returns (bytes memory) {
    bytes memory to;
    bytes memory value;
    bytes memory data;
    bytes memory txGas;
    for (uint256 i = 0; i < to_.length; i++) {
      to = abi.encodePacked(to, bytes32(uint256(uint160(to_[i]))));
      value = abi.encodePacked(value, bytes32(value_[i]));
      data = abi.encodePacked(data, data_[i]);
      txGas = abi.encodePacked(txGas, bytes32(txGas_[i]));
    }
    return
      abi.encodePacked(
        bytes4(keccak256('multiRequest(address[],uint256[],bytes[],uint256[])')),
        abi.encodePacked(to, value, data, txGas)
      );
  }

  function build_addOwner(address owner) internal pure returns (bytes memory) {
    return abi.encodePacked(bytes4(keccak256('addOwner(address)')), abi.encodePacked(bytes32(uint256(uint160(owner)))));
  }

  function build_removeOwner(address owner) internal pure returns (bytes memory) {
    return
      abi.encodePacked(bytes4(keccak256('removeOwner(address)')), abi.encodePacked(bytes32(uint256(uint160(owner)))));
  }

  function build_changeThreshold(uint16 newThreshold) internal pure returns (bytes memory) {
    return
      abi.encodePacked(bytes4(keccak256('changeThreshold(uint16)')), abi.encodePacked(bytes32(uint256(newThreshold))));
  }

  function build_replaceOwner(address oldOwner, address newOwner) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        bytes4(keccak256('replaceOwner(address,address)')),
        abi.encodePacked(bytes32(uint256(uint160(oldOwner))), bytes32(uint256(uint160(newOwner))))
      );
  }

  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    verify_revertCall(revertType_);
    multiSig_.execTransaction(to_, value_, data_, txnGas_, signatures_);

    if (revertType_ == Errors.RevertStatus.Success) {}
  }

  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_
  ) internal {
    help_execTransaction(multiSig_, prank_, to_, value_, data_, txnGas_, signatures_, Errors.RevertStatus.Success);
  }

  function help_addOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address owner_,
    Errors.RevertStatus revertType_
  ) internal {
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(!multiSig_.isOwner(owner_));
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_addOwner(owner_);
    uint256 gas = DEFAULT_GAS;
    help_execTransaction(
      multiSig_,
      prank_,
      to,
      value,
      data,
      gas,
      build_signatures(multiSig_, ownersPk_, to, value, data, gas)
    );
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(multiSig_.isOwner(owner_));
  }

  function help_addOwner(address prank_, MyMultiSig multiSig_, uint256[] memory ownersPk_, address owner_) internal {
    help_addOwner(prank_, multiSig_, ownersPk_, owner_, Errors.RevertStatus.Success);
  }

  function help_removeOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address owner_,
    Errors.RevertStatus revertType_
  ) internal {
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(multiSig_.isOwner(owner_));
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_removeOwner(owner_);
    uint256 gas = DEFAULT_GAS;
    help_execTransaction(
      multiSig_,
      prank_,
      to,
      value,
      data,
      gas,
      build_signatures(multiSig_, ownersPk_, to, value, data, gas)
    );
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(!multiSig_.isOwner(owner_));
  }

  function help_removeOwner(address prank_, MyMultiSig multiSig_, uint256[] memory ownersPk_, address owner_) internal {
    help_removeOwner(prank_, multiSig_, ownersPk_, owner_, Errors.RevertStatus.Success);
  }

  function help_changeThreshold(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    uint16 newThreshold_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_changeThreshold(newThreshold_);
    uint256 gas = DEFAULT_GAS;
    help_execTransaction(
      multiSig_,
      prank_,
      to,
      value,
      data,
      gas,
      build_signatures(multiSig_, ownersPk_, to, value, data, gas)
    );
    if (revertType_ == Errors.RevertStatus.Success) assertEq(multiSig_.threshold(), newThreshold_);
  }

  function help_changeThreshold(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    uint16 newThreshold_
  ) internal {
    help_changeThreshold(prank_, multiSig_, ownersPk_, newThreshold_, Errors.RevertStatus.Success);
  }

  function help_replaceOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address oldOwner_,
    address newOwner_,
    Errors.RevertStatus revertType_
  ) internal {
    if (revertType_ == Errors.RevertStatus.Success) {
      assertTrue(multiSig_.isOwner(oldOwner_));
      assertTrue(!multiSig_.isOwner(newOwner_));
    }
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_replaceOwner(oldOwner_, newOwner_);
    uint256 gas = DEFAULT_GAS;
    bytes memory signatures = build_signatures(multiSig_, ownersPk_, to, value, data, gas);
    help_execTransaction(multiSig_, prank_, to, value, data, gas, signatures);
    if (revertType_ == Errors.RevertStatus.Success) {
      assertTrue(!multiSig_.isOwner(oldOwner_));
      assertTrue(multiSig_.isOwner(newOwner_));
    }
  }

  function help_replaceOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address oldOwner_,
    address newOwner_
  ) internal {
    help_replaceOwner(prank_, multiSig_, ownersPk_, oldOwner_, newOwner_, Errors.RevertStatus.Success);
  }

  function help_multiRequest(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_multiRequest(to_, value_, data_, txGas_);
    uint256 gas;
    for (uint256 i = 0; i < to_.length; i++) {
      gas = txGas_[i];
    }
    bytes memory signatures = build_signatures(multiSig_, ownersPk_, to, value, data, gas);
    help_execTransaction(multiSig_, prank_, to, value, data, gas, signatures);
  }

  function help_multiRequest(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_
  ) internal {
    help_multiRequest(prank_, multiSig_, ownersPk_, to_, value_, data_, txGas_, Errors.RevertStatus.Success);
  }
}
