// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PolicyEnforcerBench } from "../PolicyEnforcer.bench.t.sol";

/// @dev Benchmarks for PolicyEnforcer.check().
contract CheckBench is PolicyEnforcerBench {
    /*/////////////////////////////////////////////////////////////////////////
                              GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_Groups1() public {
        harness.check(groups1Pass.policy, groups1Pass.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_1");
    }

    function test_Groups2_PassEarly() public {
        harness.check(groups2PassEarly.policy, groups2PassEarly.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_2_pass_early");
    }

    function test_Groups2_PassLate() public {
        harness.check(groups2PassLate.policy, groups2PassLate.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_2_pass_late");
    }

    function test_Groups4_PassEarly() public {
        harness.check(groups4PassEarly.policy, groups4PassEarly.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_4_pass_early");
    }

    function test_Groups4_PassLate() public {
        harness.check(groups4PassLate.policy, groups4PassLate.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_4_pass_late");
    }

    function test_Groups8_PassEarly() public {
        harness.check(groups8PassEarly.policy, groups8PassEarly.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_8_pass_early");
    }

    function test_Groups8_PassLate() public {
        harness.check(groups8PassLate.policy, groups8PassLate.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_8_pass_late");
    }

    function test_Groups16_PassEarly() public {
        harness.check(groups16PassEarly.policy, groups16PassEarly.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_16_pass_early");
    }

    function test_Groups16_PassLate() public {
        harness.check(groups16PassLate.policy, groups16PassLate.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "groups_16_pass_late");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              RULE SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_Rules1() public {
        harness.check(rules1Pass.policy, rules1Pass.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_1");
    }

    function test_Rules4_AllPass() public {
        harness.check(rules4AllPass.policy, rules4AllPass.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_4_all_pass");
    }

    function test_Rules4_FailFirst() public {
        harness.check(rules4FailFirst.policy, rules4FailFirst.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_4_fail_first");
    }

    function test_Rules4_FailLast() public {
        harness.check(rules4FailLast.policy, rules4FailLast.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_4_fail_last");
    }

    function test_Rules8_AllPass() public {
        harness.check(rules8AllPass.policy, rules8AllPass.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_8_all_pass");
    }

    function test_Rules8_FailMiddle() public {
        harness.check(rules8FailMiddle.policy, rules8FailMiddle.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_8_fail_middle");
    }

    function test_Rules16_AllPass() public {
        harness.check(rules16AllPass.policy, rules16AllPass.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_16_all_pass");
    }

    function test_Rules32_AllPass() public {
        harness.check(rules32AllPass.policy, rules32AllPass.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "rules_32_all_pass");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH
    /////////////////////////////////////////////////////////////////////////*/

    function test_Depth1_Elementary() public {
        harness.check(depth1Elementary.policy, depth1Elementary.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_1_elementary");
    }

    function test_Depth2_StructField() public {
        harness.check(depth2StructField.policy, depth2StructField.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_2_struct_field");
    }

    function test_Depth3_NestedStruct() public {
        harness.check(depth3NestedStruct.policy, depth3NestedStruct.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_3_nested_struct");
    }

    function test_Depth4_DeepNested() public {
        harness.check(depth4DeepNested.policy, depth4DeepNested.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_4_deep_nested");
    }

    function test_Depth8_VeryDeep() public {
        harness.check(depth8VeryDeep.policy, depth8VeryDeep.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_8_very_deep");
    }

    function test_Depth2_ArrayElem() public {
        harness.check(depth2ArrayElem.policy, depth2ArrayElem.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_2_array_elem");
    }

    function test_Depth3_ArrayStructField() public {
        harness.check(depth3ArrayStructField.policy, depth3ArrayStructField.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "depth_3_array_struct_field");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              LCP BENEFIT
    /////////////////////////////////////////////////////////////////////////*/

    function test_Lcp1_Shared4Rules() public {
        harness.check(lcp1Shared4Rules.policy, lcp1Shared4Rules.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "lcp_1_shared_4rules");
    }

    function test_Lcp3_Deep4Rules() public {
        harness.check(lcp3Deep4Rules.policy, lcp3Deep4Rules.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "lcp_3_deep_4rules");
    }

    function test_LcpIdenticalPaths() public {
        harness.check(lcpIdenticalPaths.policy, lcpIdenticalPaths.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "lcp_identical_paths");
    }

    function test_LcpNone_DisjointAtDepth2() public {
        harness.check(lcpNone4Rules.policy, lcpNone4Rules.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "lcp_none_disjoint_depth2");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_OpEq() public {
        harness.check(opEq.policy, opEq.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_eq");
    }

    function test_OpGt() public {
        harness.check(opGt.policy, opGt.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_gt");
    }

    function test_OpLt() public {
        harness.check(opLt.policy, opLt.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_lt");
    }

    function test_OpGte() public {
        harness.check(opGte.policy, opGte.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_gte");
    }

    function test_OpLte() public {
        harness.check(opLte.policy, opLte.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_lte");
    }

    function test_OpBetween() public {
        harness.check(opBetween.policy, opBetween.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_between");
    }

    function test_OpIn_2Members() public {
        harness.check(opIn2.policy, opIn2.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_2");
    }

    function test_OpIn_4Members() public {
        harness.check(opIn4.policy, opIn4.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_4");
    }

    function test_OpIn_6Members() public {
        harness.check(opIn6.policy, opIn6.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_6");
    }

    function test_OpIn_8Members() public {
        harness.check(opIn8.policy, opIn8.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_8");
    }

    function test_OpIn_16Members() public {
        harness.check(opIn16.policy, opIn16.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_16");
    }

    function test_OpIn_32Members() public {
        harness.check(opIn32.policy, opIn32.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_32");
    }

    function test_OpIn_64Members() public {
        harness.check(opIn64.policy, opIn64.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_64");
    }

    function test_OpIn_128Members() public {
        harness.check(opIn128.policy, opIn128.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_in_128");
    }

    function test_OpBitmaskAll() public {
        harness.check(opBitmaskAll.policy, opBitmaskAll.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_bitmask_all");
    }

    function test_OpBitmaskAny() public {
        harness.check(opBitmaskAny.policy, opBitmaskAny.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_bitmask_any");
    }

    function test_OpBitmaskNone() public {
        harness.check(opBitmaskNone.policy, opBitmaskNone.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_bitmask_none");
    }

    function test_OpNotEq() public {
        harness.check(opNotEq.policy, opNotEq.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_not_eq");
    }

    function test_OpNotIn_4Members() public {
        harness.check(opNotIn4.policy, opNotIn4.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "op_not_in_4");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function test_ScopeCalldataOnly() public {
        harness.check(scopeCalldataOnly.policy, scopeCalldataOnly.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "scope_calldata_only");
    }

    function test_ScopeContextOnly() public {
        harness.check(scopeContextOnly.policy, scopeContextOnly.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "scope_context_only");
    }

    function test_ScopeMixed() public {
        harness.check(scopeMixed.policy, scopeMixed.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "scope_mixed");
    }

    function test_CtxMsgSender() public {
        harness.check(scopeCtxMsgSender.policy, scopeCtxMsgSender.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "ctx_msg_sender");
    }

    function test_CtxMsgValue() public {
        harness.check(scopeCtxMsgValue.policy, scopeCtxMsgValue.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "ctx_msg_value");
    }

    function test_CtxTimestamp() public {
        harness.check(scopeCtxTimestamp.policy, scopeCtxTimestamp.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "ctx_timestamp");
    }

    function test_CtxBlockNumber() public {
        harness.check(scopeCtxBlockNumber.policy, scopeCtxBlockNumber.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "ctx_block_number");
    }

    function test_CtxChainId() public {
        harness.check(scopeCtxChainId.policy, scopeCtxChainId.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "ctx_chain_id");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              VALUE TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_TypeElementary() public {
        harness.check(typeElementary.policy, typeElementary.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_elementary");
    }

    function test_TypeAddress() public {
        harness.check(typeAddress.policy, typeAddress.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_address");
    }

    function test_TypeBytes32() public {
        harness.check(typeBytes32.policy, typeBytes32.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_bytes32");
    }

    function test_TypeStaticStruct() public {
        harness.check(typeStaticStruct.policy, typeStaticStruct.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_static_struct");
    }

    function test_TypeDynStructStatic() public {
        harness.check(typeDynStructStatic.policy, typeDynStructStatic.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_dyn_struct_static");
    }

    function test_TypeArrayElement() public {
        harness.check(typeArrayElement.policy, typeArrayElement.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_array_element");
    }

    function test_TypeStaticArrayElem() public {
        harness.check(typeStaticArrayElem.policy, typeStaticArrayElem.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_static_array_elem");
    }

    function test_TypeLargeTupleField() public {
        harness.check(typeLargeTupleField.policy, typeLargeTupleField.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "type_large_tuple_field");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              LENGTH OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_LengthEq_DynArray() public {
        harness.check(lengthEqDynArray.policy, lengthEqDynArray.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "length_eq_dyn_array");
    }

    function test_LengthGt_DynArray() public {
        harness.check(lengthGtDynArray.policy, lengthGtDynArray.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "length_gt_dyn_array");
    }

    function test_LengthBetween_Bytes() public {
        harness.check(lengthBetweenBytes.policy, lengthBetweenBytes.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "length_between_bytes");
    }

    function test_LengthLt_BytesEmpty() public {
        harness.check(lengthLtBytesEmpty.policy, lengthLtBytesEmpty.callData);
        vm.snapshotGasLastCall("PolicyEnforcer.check", "length_lt_bytes_empty");
    }
}
