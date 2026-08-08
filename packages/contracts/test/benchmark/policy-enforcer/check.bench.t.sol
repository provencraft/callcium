// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { PolicyEnforcerBench } from "../PolicyEnforcer.bench.t.sol";

/// @dev Benchmarks for PolicyEnforcer.check().
contract CheckBench is PolicyEnforcerBench {
    /*/////////////////////////////////////////////////////////////////////////
                              GROUP SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_Groups1() public {
        _benchCheckPasses(groups1Pass, "groups_1");
    }

    function test_Groups2PassFirst() public {
        _benchCheckPasses(groups2PassFirst, "groups_2_pass_first");
    }

    function test_Groups2PassLast() public {
        _benchCheckPasses(groups2PassLast, "groups_2_pass_last");
    }

    function test_Groups4PassFirst() public {
        _benchCheckPasses(groups4PassFirst, "groups_4_pass_first");
    }

    function test_Groups4PassLast() public {
        _benchCheckPasses(groups4PassLast, "groups_4_pass_last");
    }

    function test_Groups8PassFirst() public {
        _benchCheckPasses(groups8PassFirst, "groups_8_pass_first");
    }

    function test_Groups8PassLast() public {
        _benchCheckPasses(groups8PassLast, "groups_8_pass_last");
    }

    function test_Groups16PassFirst() public {
        _benchCheckPasses(groups16PassFirst, "groups_16_pass_first");
    }

    function test_Groups16PassLast() public {
        _benchCheckPasses(groups16PassLast, "groups_16_pass_last");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              RULE SCALING
    /////////////////////////////////////////////////////////////////////////*/

    function test_Rules1() public {
        _benchCheckPasses(rules1Pass, "rules_1");
    }

    function test_Rules4AllPass() public {
        _benchCheckPasses(rules4AllPass, "rules_4_all_pass");
    }

    function test_Rules4FailFirst() public {
        _benchCheckFails(rules4FailFirst, "rules_4_fail_first");
    }

    function test_Rules4FailLast() public {
        _benchCheckFails(rules4FailLast, "rules_4_fail_last");
    }

    function test_Rules8AllPass() public {
        _benchCheckPasses(rules8AllPass, "rules_8_all_pass");
    }

    function test_Rules8FailMiddle() public {
        _benchCheckFails(rules8FailMiddle, "rules_8_fail_middle");
    }

    function test_Rules16AllPass() public {
        _benchCheckPasses(rules16AllPass, "rules_16_all_pass");
    }

    /// @dev Also the value-type series' large-tuple row, which addresses 32 fields of one tuple.
    function test_Rules32AllPass() public {
        _benchCheckPasses(rules32AllPass, "rules_32_all_pass");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PATH DEPTH
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev The cheapest policy, and the baseline the operator and value-type series read against
    /// as well. Those sections once carried their own copies of it, which recorded this number by
    /// construction and could not diverge from it.
    function test_Depth1Elementary() public {
        _benchCheckPasses(elementaryEq, "depth_1_elementary");
    }

    function test_Depth8VeryDeep() public {
        _benchCheckPasses(depth8VeryDeep, "depth_8_very_deep");
    }

    /// @dev Also the value-type series' array row: no hint resolves an array element, so this is
    /// the unhinted baseline for both.
    function test_Depth2ArrayElem() public {
        _benchCheckPasses(arrayElem, "depth_2_array_elem");
    }

    function test_Depth3ArrayStructField() public {
        _benchCheckPasses(depth3ArrayStructField, "depth_3_array_struct_field");
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   HOP CHAINS
    /////////////////////////////////////////////////////////////////////////*/

    function test_Hops1() public {
        _benchCheckPasses(hops1, "hops_1");
    }

    function test_Hops2() public {
        _benchCheckPasses(hops2, "hops_2");
    }

    function test_Hops4() public {
        _benchCheckPasses(hops4, "hops_4");
    }

    function test_Hops8() public {
        _benchCheckPasses(hops8, "hops_8");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_OpGt() public {
        _benchCheckPasses(opGt, "op_gt");
    }

    function test_OpLt() public {
        _benchCheckPasses(opLt, "op_lt");
    }

    function test_OpGte() public {
        _benchCheckPasses(opGte, "op_gte");
    }

    function test_OpLte() public {
        _benchCheckPasses(opLte, "op_lte");
    }

    function test_OpBetween() public {
        _benchCheckPasses(opBetween, "op_between");
    }

    function test_OpIn2Members() public {
        _benchCheckPasses(opIn2, "op_in_2");
    }

    function test_OpIn4Members() public {
        _benchCheckPasses(opIn4, "op_in_4");
    }

    function test_OpIn6Members() public {
        _benchCheckPasses(opIn6, "op_in_6");
    }

    function test_OpIn8Members() public {
        _benchCheckPasses(opIn8, "op_in_8");
    }

    function test_OpIn16Members() public {
        _benchCheckPasses(opIn16, "op_in_16");
    }

    function test_OpIn32Members() public {
        _benchCheckPasses(opIn32, "op_in_32");
    }

    function test_OpIn64Members() public {
        _benchCheckPasses(opIn64, "op_in_64");
    }

    function test_OpIn128Members() public {
        _benchCheckPasses(opIn128, "op_in_128");
    }

    function test_OpBitmaskAll() public {
        _benchCheckPasses(opBitmaskAll, "op_bitmask_all");
    }

    function test_OpBitmaskAny() public {
        _benchCheckPasses(opBitmaskAny, "op_bitmask_any");
    }

    function test_OpBitmaskNone() public {
        _benchCheckPasses(opBitmaskNone, "op_bitmask_none");
    }

    function test_OpNotEq() public {
        _benchCheckPasses(opNotEq, "op_not_eq");
    }

    function test_OpNotIn4Members() public {
        _benchCheckPasses(opNotIn4, "op_not_in_4");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              SCOPE
    /////////////////////////////////////////////////////////////////////////*/

    function test_ScopeCalldataOnly() public {
        _benchCheckPasses(scopeCalldataOnly, "scope_calldata_only");
    }

    function test_ScopeContextOnly() public {
        _benchCheckPasses(scopeContextOnly, "scope_context_only");
    }

    function test_ScopeMixed() public {
        _benchCheckPasses(scopeMixed, "scope_mixed");
    }

    function test_CtxMsgSender() public {
        _benchCheckPasses(scopeCtxMsgSender, "ctx_msg_sender");
    }

    function test_CtxMsgValue() public {
        _benchCheckPasses(scopeCtxMsgValue, "ctx_msg_value");
    }

    function test_CtxTimestamp() public {
        _benchCheckPasses(scopeCtxTimestamp, "ctx_timestamp");
    }

    function test_CtxBlockNumber() public {
        _benchCheckPasses(scopeCtxBlockNumber, "ctx_block_number");
    }

    function test_CtxChainId() public {
        _benchCheckPasses(scopeCtxChainId, "ctx_chain_id");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              VALUE TYPES
    /////////////////////////////////////////////////////////////////////////*/

    function test_TypeAddress() public {
        _benchCheckPasses(typeAddress, "type_address");
    }

    function test_TypeBytes32() public {
        _benchCheckPasses(typeBytes32, "type_bytes32");
    }

    function test_TypeStaticStruct() public {
        _benchCheckPasses(typeStaticStruct, "type_static_struct");
    }

    function test_TypeDynStructStatic() public {
        _benchCheckPasses(typeDynStructStatic, "type_dyn_struct_static");
    }

    function test_TypeStaticArrayElem() public {
        _benchCheckPasses(typeStaticArrayElem, "type_static_array_elem");
    }

    /*/////////////////////////////////////////////////////////////////////////
                             DYNAMIC TUPLE RULES
    /////////////////////////////////////////////////////////////////////////*/

    function test_DynTupleRules1() public {
        _benchCheckPasses(dynTupleRules1, "dyn_tuple_rules_1");
    }

    function test_DynTupleRules4() public {
        _benchCheckPasses(dynTupleRules4, "dyn_tuple_rules_4");
    }

    /*/////////////////////////////////////////////////////////////////////////
                              LENGTH OPERATORS
    /////////////////////////////////////////////////////////////////////////*/

    function test_LengthEqDynArray() public {
        _benchCheckPasses(lengthEqDynArray, "length_eq_dyn_array");
    }

    function test_LengthGtDynArray() public {
        _benchCheckPasses(lengthGtDynArray, "length_gt_dyn_array");
    }

    function test_LengthBetweenBytes() public {
        _benchCheckPasses(lengthBetweenBytes, "length_between_bytes");
    }

    function test_LengthLtBytesEmpty() public {
        _benchCheckPasses(lengthLtBytesEmpty, "length_lt_bytes_empty");
    }
}
