// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { CommonBase } from "forge-std/Base.sol";
import { Script } from "forge-std/Script.sol";

import { DescriptorBuilder } from "src/DescriptorBuilder.sol";

import { CalldataMutation } from "script/CalldataMutation.sol";

struct WordAndBytes {
    /// @dev A word.
    uint256 word;
    /// @dev A byte string.
    bytes data;
}

struct AccountAndBytes {
    /// @dev An address.
    address account;
    /// @dev A byte string.
    bytes data;
}

struct WordAndAccountPairs {
    /// @dev A word.
    uint256 word;
    /// @dev Two address and byte string pairs.
    AccountAndBytes[2] pairs;
}

struct WordAndWords {
    /// @dev A word.
    uint256 word;
    /// @dev A list of words.
    uint256[] words;
}

struct WordAndPair {
    /// @dev A word.
    uint256 word;
    /// @dev Two words.
    uint256[2] pair;
}

struct WordAndAccount {
    /// @dev A word.
    uint256 word;
    /// @dev An address.
    address account;
}

struct BytesAccountsWord {
    /// @dev A byte string.
    bytes data;
    /// @dev Two word and address pairs.
    WordAndAccount[2] pairs;
    /// @dev A word.
    uint256 word;
}

struct PairAndBytes {
    /// @dev Two words.
    uint256[2] pair;
    /// @dev A byte string.
    bytes data;
}

/// @notice Each shape reads its arguments fully in two ways and returns their encoding: `Access` copies `calldata`
/// parameters element by element, `Eager` takes `memory` parameters. A value type has no data location, so the `words`
/// shape has `Eager` only.
contract SolcDecoderTarget {
    /*/////////////////////////////////////////////////////////////////////////
                                       WORDS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments.
    function wordsEager(
        uint8 narrow,
        int16 signedWord,
        address account,
        bool flag,
        bytes3 prefix
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(narrow, signedWord, account, flag, prefix);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    TUPLE ARRAY
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `items`, copied element by element.
    function tupleArrayAccess(WordAndBytes[] calldata items) external pure returns (bytes memory) {
        return abi.encode(_wordAndBytesList(items));
    }

    /// @dev Returns the encoding of `items`.
    function tupleArrayEager(WordAndBytes[] memory items) external pure returns (bytes memory) {
        return abi.encode(items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   NESTED BYTES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `items`, copied element by element.
    function nestedBytesAccess(bytes[][] calldata items) external pure returns (bytes memory) {
        bytes[][] memory copy = new bytes[][](items.length);
        for (uint256 i; i < items.length; ++i) {
            copy[i] = _bytesList(items[i]);
        }
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `items`.
    function nestedBytesEager(bytes[][] memory items) external pure returns (bytes memory) {
        return abi.encode(items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   NESTED TUPLE
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `item`, copied element by element.
    function nestedTupleAccess(WordAndAccountPairs calldata item) external pure returns (bytes memory) {
        return abi.encode(_wordAndAccountPairs(item));
    }

    /// @dev Returns the encoding of `item`.
    function nestedTupleEager(WordAndAccountPairs memory item) external pure returns (bytes memory) {
        return abi.encode(item);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    FIXED ROWS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `rows`, copied element by element.
    function fixedRowsAccess(uint256[3][] calldata rows) external pure returns (bytes memory) {
        uint256[3][] memory copy = new uint256[3][](rows.length);
        for (uint256 i; i < rows.length; ++i) {
            for (uint256 j; j < 3; ++j) {
                copy[i][j] = rows[i][j];
            }
        }
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `rows`.
    function fixedRowsEager(uint256[3][] memory rows) external pure returns (bytes memory) {
        return abi.encode(rows);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    STRING PAIR
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `texts` element by element.
    function stringPairAccess(string[2] calldata texts, uint256 word) external pure returns (bytes memory) {
        string[2] memory copy;
        for (uint256 i; i < 2; ++i) {
            copy[i] = texts[i];
        }
        return abi.encode(copy, word);
    }

    /// @dev Returns the encoding of its arguments.
    function stringPairEager(string[2] memory texts, uint256 word) external pure returns (bytes memory) {
        return abi.encode(texts, word);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                       MIXED
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `data` and `item` element by element.
    function mixedAccess(
        uint256 first,
        bytes calldata data,
        WordAndWords calldata item,
        uint256 last
    )
        external
        pure
        returns (bytes memory)
    {
        bytes memory dataCopy = data;
        return abi.encode(first, dataCopy, WordAndWords(item.word, _words(item.words)), last);
    }

    /// @dev Returns the encoding of its arguments.
    function mixedEager(
        uint256 first,
        bytes memory data,
        WordAndWords memory item,
        uint256 last
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(first, data, item, last);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 WORDS AND ACCOUNT
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `words` element by element.
    function wordsAndAccountAccess(uint256[] calldata words, address account) external pure returns (bytes memory) {
        return abi.encode(_words(words), account);
    }

    /// @dev Returns the encoding of its arguments.
    function wordsAndAccountEager(uint256[] memory words, address account) external pure returns (bytes memory) {
        return abi.encode(words, account);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    BYTES PAIRS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `items`, copied element by element.
    function bytesPairsAccess(bytes[2][] calldata items) external pure returns (bytes memory) {
        bytes[2][] memory copy = new bytes[2][](items.length);
        for (uint256 i; i < items.length; ++i) {
            for (uint256 j; j < 2; ++j) {
                copy[i][j] = items[i][j];
            }
        }
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `items`.
    function bytesPairsEager(bytes[2][] memory items) external pure returns (bytes memory) {
        return abi.encode(items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   STATIC TUPLES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `items`, copied element by element.
    function staticTuplesAccess(WordAndPair[] calldata items) external pure returns (bytes memory) {
        WordAndPair[] memory copy = new WordAndPair[](items.length);
        for (uint256 i; i < items.length; ++i) {
            copy[i] = _wordAndPair(items[i]);
        }
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `items`.
    function staticTuplesEager(WordAndPair[] memory items) external pure returns (bytes memory) {
        return abi.encode(items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    TUPLE PAIRS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `items` element by element.
    function tuplePairsAccess(uint256 word, WordAndBytes[2][] calldata items) external pure returns (bytes memory) {
        WordAndBytes[2][] memory copy = new WordAndBytes[2][](items.length);
        for (uint256 i; i < items.length; ++i) {
            for (uint256 j; j < 2; ++j) {
                copy[i][j] = _wordAndBytes(items[i][j]);
            }
        }
        return abi.encode(word, copy);
    }

    /// @dev Returns the encoding of its arguments.
    function tuplePairsEager(uint256 word, WordAndBytes[2][] memory items) external pure returns (bytes memory) {
        return abi.encode(word, items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                               TUPLE ARRAY AND WORD
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `items` element by element.
    function tupleArrayAndWordAccess(WordAndBytes[] calldata items, uint256 word) external pure returns (bytes memory) {
        return abi.encode(_wordAndBytesList(items), word);
    }

    /// @dev Returns the encoding of its arguments.
    function tupleArrayAndWordEager(WordAndBytes[] memory items, uint256 word) external pure returns (bytes memory) {
        return abi.encode(items, word);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   NESTED WORDS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `items`, copied element by element.
    function nestedWordsAccess(uint256[][] calldata items) external pure returns (bytes memory) {
        uint256[][] memory copy = new uint256[][](items.length);
        for (uint256 i; i < items.length; ++i) {
            copy[i] = _words(items[i]);
        }
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `items`.
    function nestedWordsEager(uint256[][] memory items) external pure returns (bytes memory) {
        return abi.encode(items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 BYTES FIRST TUPLE
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `item`, copied element by element.
    function bytesFirstTupleAccess(BytesAccountsWord calldata item) external pure returns (bytes memory) {
        BytesAccountsWord memory copy;
        copy.data = item.data;
        for (uint256 i; i < 2; ++i) {
            copy.pairs[i] = WordAndAccount(item.pairs[i].word, item.pairs[i].account);
        }
        copy.word = item.word;
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `item`.
    function bytesFirstTupleEager(BytesAccountsWord memory item) external pure returns (bytes memory) {
        return abi.encode(item);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   NARROW ARRAYS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `signedWords` and `prefixes`, copied element by element.
    function narrowArraysAccess(
        int8[] calldata signedWords,
        bytes2[] calldata prefixes
    )
        external
        pure
        returns (bytes memory)
    {
        int8[] memory signedCopy = new int8[](signedWords.length);
        for (uint256 i; i < signedWords.length; ++i) {
            signedCopy[i] = signedWords[i];
        }
        bytes2[] memory prefixCopy = new bytes2[](prefixes.length);
        for (uint256 i; i < prefixes.length; ++i) {
            prefixCopy[i] = prefixes[i];
        }
        return abi.encode(signedCopy, prefixCopy);
    }

    /// @dev Returns the encoding of its arguments.
    function narrowArraysEager(
        int8[] memory signedWords,
        bytes2[] memory prefixes
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(signedWords, prefixes);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                     HEAD MIX
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `triple`, `item` and `texts` element by element.
    function headMixAccess(
        uint256 word,
        uint256[3] calldata triple,
        WordAndAccountPairs calldata item,
        string[3] calldata texts
    )
        external
        pure
        returns (bytes memory)
    {
        uint256[3] memory tripleCopy;
        string[3] memory textsCopy;
        for (uint256 i; i < 3; ++i) {
            tripleCopy[i] = triple[i];
            textsCopy[i] = texts[i];
        }
        return abi.encode(word, tripleCopy, _wordAndAccountPairs(item), textsCopy);
    }

    /// @dev Returns the encoding of its arguments.
    function headMixEager(
        uint256 word,
        uint256[3] memory triple,
        WordAndAccountPairs memory item,
        string[3] memory texts
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(word, triple, item, texts);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                   STATIC BLOCKS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of its arguments, copying `grid` and `items` element by element.
    function staticBlocksAccess(
        uint256 word,
        uint256[2][3] calldata grid,
        WordAndPair[2] calldata items
    )
        external
        pure
        returns (bytes memory)
    {
        uint256[2][3] memory gridCopy;
        for (uint256 i; i < 3; ++i) {
            for (uint256 j; j < 2; ++j) {
                gridCopy[i][j] = grid[i][j];
            }
        }
        WordAndPair[2] memory itemsCopy;
        for (uint256 i; i < 2; ++i) {
            itemsCopy[i] = _wordAndPair(items[i]);
        }
        return abi.encode(word, gridCopy, itemsCopy);
    }

    /// @dev Returns the encoding of its arguments.
    function staticBlocksEager(
        uint256 word,
        uint256[2][3] memory grid,
        WordAndPair[2] memory items
    )
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(word, grid, items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                  PAIRS IN TUPLES
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns the encoding of `items`, copied element by element.
    function pairsInTuplesAccess(PairAndBytes[] calldata items) external pure returns (bytes memory) {
        PairAndBytes[] memory copy = new PairAndBytes[](items.length);
        for (uint256 i; i < items.length; ++i) {
            for (uint256 j; j < 2; ++j) {
                copy[i].pair[j] = items[i].pair[j];
            }
            copy[i].data = items[i].data;
        }
        return abi.encode(copy);
    }

    /// @dev Returns the encoding of `items`.
    function pairsInTuplesEager(PairAndBytes[] memory items) external pure returns (bytes memory) {
        return abi.encode(items);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns a copy of `words`.
    function _words(uint256[] calldata words) private pure returns (uint256[] memory copy) {
        copy = new uint256[](words.length);
        for (uint256 i; i < words.length; ++i) {
            copy[i] = words[i];
        }
    }

    /// @dev Returns a copy of `items`.
    function _bytesList(bytes[] calldata items) private pure returns (bytes[] memory copy) {
        copy = new bytes[](items.length);
        for (uint256 i; i < items.length; ++i) {
            copy[i] = items[i];
        }
    }

    /// @dev Returns a copy of `item`.
    function _wordAndBytes(WordAndBytes calldata item) private pure returns (WordAndBytes memory) {
        return WordAndBytes(item.word, item.data);
    }

    /// @dev Returns a copy of `items`.
    function _wordAndBytesList(WordAndBytes[] calldata items) private pure returns (WordAndBytes[] memory copy) {
        copy = new WordAndBytes[](items.length);
        for (uint256 i; i < items.length; ++i) {
            copy[i] = _wordAndBytes(items[i]);
        }
    }

    /// @dev Returns a copy of `item`.
    function _wordAndAccountPairs(WordAndAccountPairs calldata item)
        private
        pure
        returns (WordAndAccountPairs memory copy)
    {
        copy.word = item.word;
        for (uint256 i; i < 2; ++i) {
            copy.pairs[i] = AccountAndBytes(item.pairs[i].account, item.pairs[i].data);
        }
    }

    /// @dev Returns a copy of `item`.
    function _wordAndPair(WordAndPair calldata item) private pure returns (WordAndPair memory copy) {
        copy.word = item.word;
        for (uint256 j; j < 2; ++j) {
            copy.pair[j] = item.pair[j];
        }
    }
}

/// @notice Writes a corpus of Solidity decoder readings: for each shape, canonical payloads and a mutation of each,
/// read by every reader of the target. One line per reader that accepts: `reader descriptor calldata encoding`, where
/// `encoding` is the reader's encoding of the arguments it read.
contract LeanDecoderFidelityWriter is CalldataMutation {
    uint256 internal constant SHAPE_COUNT = 18;
    uint256 internal constant WORDS = 0;

    uint256 internal constant READER_COUNT = 2;
    uint256 internal constant ACCESS = 0;
    uint256 internal constant EAGER = 1;

    uint256 internal constant CALL_GAS = 30_000_000;

    string internal constant CORPUS = "out/decoder-fidelity.txt";

    SolcDecoderTarget internal target;

    /// @dev Deploys the target and starts a fresh corpus.
    constructor() {
        target = new SolcDecoderTarget();
        if (vm.exists(CORPUS)) vm.removeFile(CORPUS);
    }

    /// @dev Writes `cases` cases of every shape.
    function writeAll(uint256 cases) external {
        for (uint256 shape; shape < SHAPE_COUNT; ++shape) {
            for (uint256 i; i < cases; ++i) {
                this.writeCase(shape);
            }
        }
    }

    /// @dev Writes the lines of one case. External, so each case runs in fresh memory.
    function writeCase(uint256 shape) external {
        bytes memory payload = _generate(shape);
        _write(shape, payload, true);
        _write(shape, mutate(payload), false);
    }

    /*/////////////////////////////////////////////////////////////////////////
                                      CORPUS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Writes a line per reader of `shape` that accepts `payload`, which reads back unchanged when `canonical`.
    function _write(uint256 shape, bytes memory payload, bool canonical) private {
        (string memory name, string memory types) = _shape(shape);
        string memory descriptor = vm.toString(DescriptorBuilder.fromTypes(types));
        for (uint256 reader; reader < READER_COUNT; ++reader) {
            if (shape == WORDS && reader == ACCESS) continue;
            bytes memory callData = bytes.concat(_selector(name, _suffix(reader), types), payload);
            // No input in the corpus needs `CALL_GAS`, so a call that spends it all crashed.
            uint256 gasBefore = gasleft();
            (bool success, bytes memory returned) = address(target).call{ gas: CALL_GAS }(callData);
            require(gasBefore - gasleft() < CALL_GAS, "reader ran out of gas");
            if (canonical) require(success, "canonical payload rejected");
            if (!success) continue;
            bytes memory encoding = abi.decode(returned, (bytes));
            if (canonical) {
                require(keccak256(encoding) == keccak256(payload), "canonical payload read back differently");
            }
            vm.writeLine(
                CORPUS,
                string.concat(_suffix(reader), " ", descriptor, " ", vm.toString(callData), " ", vm.toString(encoding))
            );
        }
    }

    /// @dev Returns the function name stem and argument type list of `shape`.
    function _shape(uint256 shape) private pure returns (string memory name, string memory types) {
        string[SHAPE_COUNT] memory names = [
            "words",
            "tupleArray",
            "nestedBytes",
            "nestedTuple",
            "fixedRows",
            "stringPair",
            "mixed",
            "wordsAndAccount",
            "bytesPairs",
            "staticTuples",
            "tuplePairs",
            "tupleArrayAndWord",
            "nestedWords",
            "bytesFirstTuple",
            "narrowArrays",
            "headMix",
            "staticBlocks",
            "pairsInTuples"
        ];
        string[SHAPE_COUNT] memory typeLists = [
            "uint8,int16,address,bool,bytes3",
            "(uint256,bytes)[]",
            "bytes[][]",
            "(uint256,(address,bytes)[2])",
            "uint256[3][]",
            "string[2],uint256",
            "uint256,bytes,(uint256,uint256[]),uint256",
            "uint256[],address",
            "bytes[2][]",
            "(uint256,uint256[2])[]",
            "uint256,(uint256,bytes)[2][]",
            "(uint256,bytes)[],uint256",
            "uint256[][]",
            "(bytes,(uint256,address)[2],uint256)",
            "int8[],bytes2[]",
            "uint256,uint256[3],(uint256,(address,bytes)[2]),string[3]",
            "uint256,uint256[2][3],(uint256,uint256[2])[2]",
            "(uint256[2],bytes)[]"
        ];
        return (names[shape], typeLists[shape]);
    }

    /// @dev Returns the function name suffix of `reader`.
    function _suffix(uint256 reader) private pure returns (string memory) {
        return reader == ACCESS ? "Access" : "Eager";
    }

    /// @dev Returns the selector of the function named by `name` and `suffix` that takes `types`.
    function _selector(string memory name, string memory suffix, string memory types) private pure returns (bytes4) {
        return bytes4(keccak256(bytes(string.concat(name, suffix, "(", types, ")"))));
    }

    /*/////////////////////////////////////////////////////////////////////////
                                    GENERATORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns a canonical payload of `shape`.
    function _generate(uint256 shape) private view returns (bytes memory) {
        if (shape == WORDS) {
            return abi.encode(
                uint8(vm.randomUint()),
                int16(uint16(vm.randomUint())),
                address(uint160(vm.randomUint())),
                below(2) == 0,
                bytes3(uint24(vm.randomUint()))
            );
        }
        if (shape == 1) return abi.encode(_wordAndBytesList());
        if (shape == 2) {
            bytes[][] memory items = new bytes[][](below(4));
            for (uint256 i; i < items.length; ++i) {
                items[i] = new bytes[](below(3));
                for (uint256 j; j < items[i].length; ++j) {
                    items[i][j] = randomBytes(40);
                }
            }
            return abi.encode(items);
        }
        if (shape == 3) return abi.encode(_wordAndAccountPairs());
        if (shape == 4) {
            uint256[3][] memory rows = new uint256[3][](below(5));
            for (uint256 i; i < rows.length; ++i) {
                rows[i] = [_word(), _word(), _word()];
            }
            return abi.encode(rows);
        }
        if (shape == 5) return abi.encode([string(randomBytes(40)), string(randomBytes(40))], _word());
        if (shape == 6) {
            return abi.encode(_word(), randomBytes(40), WordAndWords(_word(), _randomWords(5)), _word());
        }
        if (shape == 7) return abi.encode(_randomWords(5), address(uint160(vm.randomUint())));
        if (shape == 8) {
            bytes[2][] memory items = new bytes[2][](below(4));
            for (uint256 i; i < items.length; ++i) {
                items[i] = [randomBytes(40), randomBytes(40)];
            }
            return abi.encode(items);
        }
        if (shape == 9) {
            WordAndPair[] memory items = new WordAndPair[](below(4));
            for (uint256 i; i < items.length; ++i) {
                items[i] = _wordAndPair();
            }
            return abi.encode(items);
        }
        if (shape == 10) {
            WordAndBytes[2][] memory items = new WordAndBytes[2][](below(3));
            for (uint256 i; i < items.length; ++i) {
                items[i] = [_wordAndBytes(), _wordAndBytes()];
            }
            return abi.encode(_word(), items);
        }
        if (shape == 11) return abi.encode(_wordAndBytesList(), _word());
        if (shape == 12) {
            uint256[][] memory items = new uint256[][](below(4));
            for (uint256 i; i < items.length; ++i) {
                items[i] = _randomWords(3);
            }
            return abi.encode(items);
        }
        if (shape == 13) {
            WordAndAccount[2] memory accounts = [
                WordAndAccount(_word(), address(uint160(vm.randomUint()))),
                WordAndAccount(_word(), address(uint160(vm.randomUint())))
            ];
            return abi.encode(BytesAccountsWord(randomBytes(40), accounts, _word()));
        }
        if (shape == 14) {
            int8[] memory signedWords = new int8[](below(5));
            for (uint256 i; i < signedWords.length; ++i) {
                signedWords[i] = int8(uint8(vm.randomUint()));
            }
            bytes2[] memory prefixes = new bytes2[](below(4));
            for (uint256 i; i < prefixes.length; ++i) {
                prefixes[i] = bytes2(uint16(vm.randomUint()));
            }
            return abi.encode(signedWords, prefixes);
        }
        if (shape == 15) {
            return abi.encode(
                _word(),
                [_word(), _word(), _word()],
                _wordAndAccountPairs(),
                [string(randomBytes(40)), string(randomBytes(40)), string(randomBytes(40))]
            );
        }
        if (shape == 16) {
            uint256[2][3] memory grid;
            for (uint256 i; i < 3; ++i) {
                grid[i] = [_word(), _word()];
            }
            return abi.encode(_word(), grid, [_wordAndPair(), _wordAndPair()]);
        }
        PairAndBytes[] memory pairs = new PairAndBytes[](below(4));
        for (uint256 i; i < pairs.length; ++i) {
            pairs[i] = PairAndBytes([_word(), _word()], randomBytes(40));
        }
        return abi.encode(pairs);
    }

    /// @dev A word, small for half the draws so that it can pass as an offset or a length once mutated into place.
    function _word() private view returns (uint256) {
        uint256 entropy = vm.randomUint();
        return entropy % 2 == 0 ? entropy >> 1 : (entropy >> 1) % 256;
    }

    /// @dev Returns a list of up to `maxCount` words.
    function _randomWords(uint256 maxCount) private view returns (uint256[] memory words) {
        words = new uint256[](below(maxCount + 1));
        for (uint256 i; i < words.length; ++i) {
            words[i] = _word();
        }
    }

    /// @dev Returns a word and byte string pair.
    function _wordAndBytes() private view returns (WordAndBytes memory) {
        return WordAndBytes(_word(), randomBytes(40));
    }

    /// @dev Returns a list of word and byte string pairs.
    function _wordAndBytesList() private view returns (WordAndBytes[] memory items) {
        items = new WordAndBytes[](below(5));
        for (uint256 i; i < items.length; ++i) {
            items[i] = _wordAndBytes();
        }
    }

    /// @dev Returns a word and two address and byte string pairs.
    function _wordAndAccountPairs() private view returns (WordAndAccountPairs memory item) {
        item.word = _word();
        for (uint256 i; i < 2; ++i) {
            item.pairs[i] = AccountAndBytes(address(uint160(vm.randomUint())), randomBytes(40));
        }
    }

    /// @dev Returns a word and a pair of words.
    function _wordAndPair() private view returns (WordAndPair memory) {
        return WordAndPair(_word(), [_word(), _word()]);
    }
}

/// @notice Writes the decoder-fidelity corpus that `lake exe decoder-fidelity` checks the Lean decoder model against.
contract LeanDecoderFidelity is Script {
    /// @dev Writes `cases` cases per shape, drawn from Foundry's random cheatcodes.
    function run(uint256 cases) public {
        new LeanDecoderFidelityWriter().writeAll(cases);
    }
}
