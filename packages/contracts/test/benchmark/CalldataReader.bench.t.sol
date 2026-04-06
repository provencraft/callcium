// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DescriptorBuilder } from "src/DescriptorBuilder.sol";
import { TypeDesc } from "src/TypeDesc.sol";

import { CalldataReaderTest } from "../unit/CalldataReader.t.sol";

// forge-lint: disable-next-item(unsafe-typecast)
abstract contract CalldataReaderBench is CalldataReaderTest {
    bytes internal descElementary;
    bytes internal callDataElementary;

    bytes internal descStaticStruct;
    bytes internal callDataStaticStruct;

    bytes internal descDynStruct;
    bytes internal callDataDynStruct;

    bytes internal descDynArraySmall;
    bytes internal callDataDynArraySmall;

    bytes internal descDynArrayMedium;
    bytes internal callDataDynArrayMedium;

    bytes internal descDynArrayLarge;
    bytes internal callDataDynArrayLarge;

    bytes internal descStaticArray;
    bytes internal callDataStaticArray;

    bytes internal descBytesArray;
    bytes internal callDataBytesArray;

    bytes internal descNested2;
    bytes internal callDataNested2;

    bytes internal descNested3;
    bytes internal callDataNested3;

    bytes internal descNested4;
    bytes internal callDataNested4;

    bytes internal descBytes;
    bytes internal callDataBytesSmall;
    bytes internal callDataBytesMedium;
    bytes internal callDataBytesLarge;
    bytes internal callDataBytesEmpty;

    bytes internal callDataDynArrayEmpty;

    bytes internal descStaticArray32;
    bytes internal callDataStaticArray32;

    bytes internal descStaticTuple10;
    bytes internal callDataStaticTuple10;

    bytes internal descStaticTuple32;
    bytes internal callDataStaticTuple32;

    bytes internal descDynTuple10;
    bytes internal callDataDynTuple10;

    bytes internal descMixedTuple10;
    bytes internal callDataMixedTuple10;

    bytes internal descNested8;
    bytes internal callDataNested8;

    function setUp() public virtual override {
        super.setUp();
        _buildFixtures();
    }

    function _buildFixtures() internal {
        _buildElementaryFixtures();
        _buildStructFixtures();
        _buildArrayFixtures();
        _buildNestedFixtures();
        _buildBytesFixtures();
        _buildLargeTupleFixtures();
        _buildDeepNestedFixtures();
    }

    function _buildElementaryFixtures() internal {
        descElementary = DescriptorBuilder.fromTypes("uint256");
        callDataElementary = abi.encodeWithSelector(SELECTOR, uint256(42));
    }

    function _buildStructFixtures() internal {
        descStaticStruct = DescriptorBuilder.fromTypes("(address,uint256)");
        callDataStaticStruct = abi.encodeWithSelector(SELECTOR, address(1), uint256(42));

        descDynStruct = DescriptorBuilder.fromTypes("(address,bytes)");
        callDataDynStruct = abi.encodeWithSelector(SELECTOR, address(1), hex"0102");
    }

    function _buildArrayFixtures() internal {
        descDynArraySmall = DescriptorBuilder.fromTypes("uint256[]");
        descDynArrayMedium = descDynArraySmall;
        descDynArrayLarge = descDynArraySmall;

        uint256[] memory small = new uint256[](3);
        small[0] = 1;
        small[1] = 2;
        small[2] = 3;
        callDataDynArraySmall = abi.encodeWithSelector(SELECTOR, small);

        uint256[] memory medium = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            medium[i] = i;
        }
        callDataDynArrayMedium = abi.encodeWithSelector(SELECTOR, medium);

        uint256[] memory large = new uint256[](100);
        for (uint256 i; i < 100; ++i) {
            large[i] = i;
        }
        callDataDynArrayLarge = abi.encodeWithSelector(SELECTOR, large);

        descStaticArray = DescriptorBuilder.fromTypes("uint256[5]");
        uint256[5] memory staticArr = [uint256(1), uint256(2), uint256(3), uint256(4), uint256(5)];
        callDataStaticArray = abi.encodeWithSelector(SELECTOR, staticArr);

        descStaticArray32 = DescriptorBuilder.fromTypes("uint256[32]");
        uint256[32] memory staticArr32;
        for (uint256 i; i < 32; ++i) {
            staticArr32[i] = i;
        }
        callDataStaticArray32 = abi.encodeWithSelector(SELECTOR, staticArr32);

        uint256[] memory emptyArr = new uint256[](0);
        callDataDynArrayEmpty = abi.encodeWithSelector(SELECTOR, emptyArr);

        descBytesArray = DescriptorBuilder.fromTypes("bytes[]");
        bytes[] memory bytesArr = new bytes[](3);
        bytesArr[0] = hex"01";
        bytesArr[1] = hex"0203";
        bytesArr[2] = hex"040506";
        callDataBytesArray = abi.encodeWithSelector(SELECTOR, bytesArr);
    }

    function _buildNestedFixtures() internal {
        bytes memory pairDesc = TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uint256_());

        descNested2 = DescriptorBuilder.create().add(TypeDesc.tuple_(pairDesc, TypeDesc.uint256_())).build();
        callDataNested2 = abi.encodeWithSelector(SELECTOR, address(1), uint256(42), uint256(100));

        bytes memory nestedDesc = TypeDesc.tuple_(pairDesc, TypeDesc.uint256_());
        descNested3 = DescriptorBuilder.create().add(TypeDesc.tuple_(nestedDesc, TypeDesc.address_())).build();
        callDataNested3 = abi.encodeWithSelector(SELECTOR, address(1), uint256(42), uint256(100), address(2));

        bytes memory deepDesc = TypeDesc.tuple_(nestedDesc, TypeDesc.address_());
        descNested4 = DescriptorBuilder.create().add(deepDesc).build();
        callDataNested4 = abi.encodeWithSelector(SELECTOR, address(1), uint256(42), uint256(100), address(2));
    }

    function _buildBytesFixtures() internal {
        descBytes = DescriptorBuilder.fromTypes("bytes");

        bytes memory smallBytes = new bytes(32);
        for (uint256 i; i < 32; ++i) {
            smallBytes[i] = bytes1(uint8(i));
        }
        callDataBytesSmall = abi.encodeWithSelector(SELECTOR, smallBytes);

        bytes memory mediumBytes = new bytes(256);
        for (uint256 i; i < 256; ++i) {
            mediumBytes[i] = bytes1(uint8(i));
        }
        callDataBytesMedium = abi.encodeWithSelector(SELECTOR, mediumBytes);

        bytes memory largeBytes = new bytes(1024);
        for (uint256 i; i < 1024; ++i) {
            largeBytes[i] = bytes1(uint8(i % 256));
        }
        callDataBytesLarge = abi.encodeWithSelector(SELECTOR, largeBytes);

        callDataBytesEmpty = abi.encodeWithSelector(SELECTOR, hex"");
    }

    function _buildLargeTupleFixtures() internal {
        descStaticTuple10 = DescriptorBuilder.create()
            .add(
                TypeDesc.tuple_(
                    TypeDesc.address_(),
                    TypeDesc.uint256_(),
                    TypeDesc.address_(),
                    TypeDesc.uint256_(),
                    TypeDesc.address_(),
                    TypeDesc.uint256_(),
                    TypeDesc.address_(),
                    TypeDesc.uint256_(),
                    TypeDesc.address_(),
                    TypeDesc.uint256_()
                )
            ).build();
        callDataStaticTuple10 = abi.encodeWithSelector(
            SELECTOR,
            address(1),
            uint256(2),
            address(3),
            uint256(4),
            address(5),
            uint256(6),
            address(7),
            uint256(8),
            address(9),
            uint256(10)
        );

        bytes[] memory fields32 = new bytes[](32);
        for (uint256 i; i < 32; ++i) {
            fields32[i] = (i % 2 == 0) ? TypeDesc.address_() : TypeDesc.uint256_();
        }
        descStaticTuple32 = DescriptorBuilder.create().add(TypeDesc.tuple_(fields32)).build();
        callDataStaticTuple32 = abi.encodeWithSelector(
            SELECTOR,
            address(1),
            uint256(2),
            address(3),
            uint256(4),
            address(5),
            uint256(6),
            address(7),
            uint256(8),
            address(9),
            uint256(10),
            address(11),
            uint256(12),
            address(13),
            uint256(14),
            address(15),
            uint256(16),
            address(17),
            uint256(18),
            address(19),
            uint256(20),
            address(21),
            uint256(22),
            address(23),
            uint256(24),
            address(25),
            uint256(26),
            address(27),
            uint256(28),
            address(29),
            uint256(30),
            address(31),
            uint256(32)
        );

        descDynTuple10 = DescriptorBuilder.create()
            .add(
                TypeDesc.tuple_(
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_(),
                    TypeDesc.bytes_()
                )
            ).build();
        callDataDynTuple10 = abi.encodeWithSelector(
            SELECTOR, hex"01", hex"02", hex"03", hex"04", hex"05", hex"06", hex"07", hex"08", hex"09", hex"0a"
        );

        descMixedTuple10 = DescriptorBuilder.create()
            .add(
                TypeDesc.tuple_(
                    TypeDesc.bytes_(),
                    TypeDesc.uint256_(),
                    TypeDesc.bytes_(),
                    TypeDesc.uint256_(),
                    TypeDesc.bytes_(),
                    TypeDesc.uint256_(),
                    TypeDesc.bytes_(),
                    TypeDesc.uint256_(),
                    TypeDesc.bytes_(),
                    TypeDesc.uint256_()
                )
            ).build();
        callDataMixedTuple10 = abi.encodeWithSelector(
            SELECTOR,
            hex"01",
            uint256(2),
            hex"03",
            uint256(4),
            hex"05",
            uint256(6),
            hex"07",
            uint256(8),
            hex"09",
            uint256(10)
        );
    }

    function _buildDeepNestedFixtures() internal {
        bytes memory level1 = TypeDesc.tuple_(TypeDesc.address_(), TypeDesc.uint256_());
        bytes memory level2 = TypeDesc.tuple_(level1, TypeDesc.uint256_());
        bytes memory level3 = TypeDesc.tuple_(level2, TypeDesc.uint256_());
        bytes memory level4 = TypeDesc.tuple_(level3, TypeDesc.uint256_());
        bytes memory level5 = TypeDesc.tuple_(level4, TypeDesc.uint256_());
        bytes memory level6 = TypeDesc.tuple_(level5, TypeDesc.uint256_());
        bytes memory level7 = TypeDesc.tuple_(level6, TypeDesc.uint256_());
        bytes memory level8 = TypeDesc.tuple_(level7, TypeDesc.uint256_());

        descNested8 = DescriptorBuilder.create().add(level8).build();
        callDataNested8 = abi.encodeWithSelector(
            SELECTOR,
            address(1),
            uint256(2),
            uint256(3),
            uint256(4),
            uint256(5),
            uint256(6),
            uint256(7),
            uint256(8),
            uint256(9)
        );
    }
}
