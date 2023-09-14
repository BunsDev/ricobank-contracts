// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { Flasher } from "./Flasher.sol";
import { RicoSetUp, Guy, WethLike } from "./RicoHelper.sol";
import "./UniHelper.sol";
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import '../src/mixin/math.sol';
import { OverrideableGem } from './mixin/OverrideableGem.sol';
import { UniNFTHook } from '../src/hook/nfpm/UniV3NFTHook.sol';
import { IERC721, INonfungiblePositionManager } from './Univ3Interface.sol';
import { File } from '../src/file.sol';
import { Bank } from '../src/bank.sol';

contract NFTHookTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address[] gems;
    uint256[] wads;
    Flasher public chap;
    address public achap;
    uint public constant flash_size = 100;
    uint goldwethtokid;
    uint golddaitokid;
    address constant public UNI_NFT_ADDR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function setUp() public {
        make_bank();
        init_gold();
        init_dai();
        uint160 onex96 = 2 ** 96;
        WethLike(WETH).deposit{value: 10000 * WAD}();
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1000 * WAD), Asset(WETH, 1000 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );
        (goldwethtokid,,,) = create_and_join_pool(args);

        args = PoolArgs(
            Asset(agold, 1000 * WAD), Asset(DAI, 1000 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );
        (golddaitokid,,,) = create_and_join_pool(args);
        IERC721(UNI_NFT_ADDR).approve(bank, goldwethtokid);
        IERC721(UNI_NFT_ADDR).approve(bank, golddaitokid);

        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(WETH))), bytes32(bytes20(address(mdn))));
        Vat(bank).filh(uilk, 'ftag', single(bytes32(bytes20(WETH))), wrtag);
 
        feedpush(wrtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(agold))), bytes32(bytes20(address(mdn))));
        Vat(bank).filh(uilk, 'ftag', single(bytes32(bytes20(agold))), grtag);
 
        feedpush(grtag, bytes32(1900 * RAY), type(uint).max);
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(DAI))), bytes32(bytes20(address(mdn))));
        Vat(bank).filh(uilk, 'ftag', single(bytes32(bytes20(DAI))), drtag);
 
        feedpush(drtag, bytes32(RAY), type(uint).max);

        Vat(bank).filk(uilk, 'line', bytes32(100000 * RAD));
        guy = new Guy(bank);
    }

    function test_nft_frob() public {
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        uint ricobefore = rico.balanceOf(self);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        Vat(bank).frob(uilk, self, addgwpos, int(WAD));
        assertGt(rico.balanceOf(self), ricobefore);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
    }

    function test_id_must_exist() public {
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        Vat(bank).frob(uilk, self, addgwpos, int(WAD));
        uint fake_id = 2 ** 100;
        bytes memory add_fake_pos = abi.encodePacked(int(1), fake_id);
        vm.expectRevert("ERC721: operator query for nonexistent token");
        Vat(bank).frob(uilk, self, add_fake_pos, int(0));
    }

    function test_cant_add_multi_dups() public {
        bytes memory add_dup_pos = abi.encodePacked(int(1), goldwethtokid, goldwethtokid);
        vm.expectRevert("ERC721: transfer of token that is not own");
        Vat(bank).frob(uilk, self, add_dup_pos, int(WAD));
    }

    function test_cant_add_dups() public {
        bytes memory add_gw_pos = abi.encodePacked(int(1), goldwethtokid);
        Vat(bank).frob(uilk, self, add_gw_pos, int(WAD));
        vm.expectRevert("ERC721: transfer of token that is not own");
        Vat(bank).frob(uilk, self, add_gw_pos, int(WAD));
    }

    function test_max_urn_nfts() public {
        uint nft_id;
        uint160 onex96 = 2 ** 96;
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1 * WAD), Asset(WETH, 1 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );

        for(uint i = 0; i < HOOK_ROOM + 1; i++) {
            (nft_id,,,) = join_pool(args);
            IERC721(UNI_NFT_ADDR).approve(bank, nft_id);
            bytes memory add_pos = abi.encodePacked(int(1), nft_id);
            if(i == HOOK_ROOM) vm.expectRevert(UniNFTHook.ErrFull.selector);
            Vat(bank).frob(uilk, self, add_pos, int(0));
        }
    }

    function test_nft_bail() public {
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        Vat(bank).frob(uilk, self, addgwpos, int(WAD));

        // just gold dip can't make collateral worthless
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(uilk, self);
        feedpush(grtag, bytes32(1900 * RAY), type(uint).max);

        // just weth dip can't make collateral worthless
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(uilk, self);

        // both dip, collateral is worthless
        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        Vat(bank).bail(uilk, self);
        assertEq(Vat(bank).urns(uilk, self), 0);
        // todo test successful swaps, compare to master
    }

    function test_nft_bail_price() public {
        // the NFT has 1000 each of gold and weth, valued at 1900 and 1000
        // frob to max safe debt with double cratio, 1.45MM rico
        File(bank).file('ceil', bytes32(WAD * 1_000_000_000));
        Vat(bank).filk(uilk, 'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filk(gilk,      'line', bytes32(RAD * 1_000_000_000));
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        uint borrow = WAD * uint(2_900_000 - 1);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        Vat(bank).frob(uilk, self, addgwpos, int(borrow));
        assertEq(nfpm.ownerOf(goldwethtokid), bank);

        // set prices to 75%
        feedpush(wrtag, bytes32(750 * RAY), type(uint).max);
        feedpush(grtag, bytes32(1425 * RAY), type(uint).max);

        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        uint expected = wmul(borrow, wmul(WAD * 75 / 100, WAD * 75 / 100));
        // tiny errors from uni pool?
        expected = expected * 10001 / 10000;
        rico_mint(expected, false);
        rico.transfer(address(guy), expected);
        guy.bail(uilk, self);

        // guy was given about exact amount, check almost all was spent
        assertLt(rico.balanceOf(address(guy)), borrow / 10_000);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));
    }

    function test_nft_bail_refund() public {
        // the NFT has 1000 each of gold and weth, valued at 1900 and 1000
        // frob to max safe debt with double cratio, 1.45MM rico
        File(bank).file('ceil', bytes32(WAD * 1_000_000_000));
        Vat(bank).filk(uilk, 'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filk(gilk,      'line', bytes32(RAD * 1_000_000_000));
        Vat(bank).filk(uilk, 'liqr', bytes32(RAY * 2));
        bytes memory addgwpos = abi.encodePacked(int(1), goldwethtokid);
        uint borrow = WAD * uint(1_450_000 - 1);
        Vat(bank).frob(uilk, self, addgwpos, int(borrow));

        // set prices to 75%
        feedpush(wrtag, bytes32(750 * RAY), type(uint).max);
        feedpush(grtag, bytes32(1425 * RAY), type(uint).max);

        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        uint expected_cost_for_keeper = wmul(borrow * 2, wmul(WAD * 75 / 100, WAD * 75 / 100));
        // tiny errors from uni pool?
        expected_cost_for_keeper = expected_cost_for_keeper * 10001 / 10000;
        rico_mint(expected_cost_for_keeper, false);
        rico.transfer(address(guy), expected_cost_for_keeper);
        uint self_pre_bail_rico = rico.balanceOf(self);
        guy.bail(uilk, self);

        // although position was overcollateralised full expected amount should be taken
        assertLt(rico.balanceOf(address(guy)), borrow / 1_000);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));

        // refund should be in the form of rico paid to self
        uint refund = rico.balanceOf(self) - self_pre_bail_rico;
        uint expected_refund = expected_cost_for_keeper - borrow;
        assertClose(refund, expected_refund, 1000);
    }

    function test_multipos() public {
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid, golddaitokid);
        Vat(bank).frob(uilk, self, data, int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);

        feedpush(grtag, bytes32(0 * RAY), type(uint).max);
        feedpush(wrtag, bytes32(0 * RAY), type(uint).max);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(uilk, self);

        feedpush(drtag, bytes32(RAY / uint(100_000)), type(uint).max);
        (,uint rush, uint cut) = Vat(bank).safe(uilk, self);
        uint wad_cost = cut / RAY * rush / RAY;
        rico_mint(wad_cost, true);
        rico.transfer(address(guy), wad_cost);
        uint guy_rico_before = rico.balanceOf(address(guy));

        uint gas = gasleft();
        guy.bail(uilk, self);
        check_gas(gas, 259791);

        assertLt(rico.balanceOf(address(guy)), guy_rico_before);
        assertEq(nfpm.ownerOf(goldwethtokid), address(guy));
        assertEq(nfpm.ownerOf(golddaitokid), address(guy));
    }

    function test_nft_frob_down() public {
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid, golddaitokid);
        Vat(bank).frob(uilk, self, data, int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);

        // remove golddaitokid
        data = abi.encodePacked(-int(1), golddaitokid);
        Vat(bank).frob(uilk, self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), self);
        (Vat.Spot spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // put it back
        data = abi.encodePacked(int(1), golddaitokid);
        nfpm.approve(bank, golddaitokid);
        Vat(bank).frob(uilk, self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // remove goldwethtokid
        data = abi.encodePacked(-int(1), goldwethtokid);
        Vat(bank).frob(uilk, self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        assertEq(nfpm.ownerOf(golddaitokid), bank);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        // put it back
        data = abi.encodePacked(int(1), goldwethtokid);
        nfpm.approve(bank, goldwethtokid);
        Vat(bank).frob(uilk, self, data, 0);
        assertEq(nfpm.ownerOf(goldwethtokid), bank);
        assertEq(nfpm.ownerOf(golddaitokid), bank);

        // remove both
        data = abi.encodePacked(-int(1), golddaitokid, goldwethtokid);
        rico_mint(100, true); // rounding
        Vat(bank).frob(uilk, self, data, -int(WAD));
        assertEq(nfpm.ownerOf(goldwethtokid), self);
        assertEq(nfpm.ownerOf(golddaitokid), self);
        assertEq(abi.decode(Vat(bank).ink(uilk, self), (uint[])).length, 0);
    }

    function test_nft_make_unsafe_by_rack() public {
        feedpush(drtag, bytes32(RAY), type(uint).max);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        feedpush(wrtag, bytes32(RAY), type(uint).max);
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid, golddaitokid);
        Vat(bank).frob(uilk, self, data, int(900 * WAD));

        feedpush(drtag, bytes32(0), type(uint).max);
        (Vat.Spot spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);
        feedpush(grtag, bytes32(0), type(uint).max);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Safe);

        skip(BANKYEAR * 10);
        Vat(bank).drip(uilk);
        (spot,,) = Vat(bank).safe(uilk, self);
        assertTrue(spot == Vat.Spot.Sunk);

        (,uint cut, uint rush) = Vat(bank).safe(uilk, self);
        uint wad_cost = cut / RAY * rush / RAY;
        rico_mint(wad_cost, true);

        bytes memory ids = Vat(bank).bail(uilk, self);
        uint256[] memory tok_ids = new uint256[](ids.length / 32);
        // convert bytes to uints by putting bytes mem into uint array
        for (uint i = 32; i <= ids.length; i += 32) {
            assembly { mstore(add(tok_ids, i), mload(add(ids, i))) }
        }

        // assert result returned from bail gives all tokens bought
        assertEq(tok_ids[0], goldwethtokid);
        assertEq(tok_ids[1], golddaitokid);
    }

    function test_dir_zero() public {
        feedpush(drtag, bytes32(RAY), type(uint).max);
        feedpush(grtag, bytes32(RAY), type(uint).max);
        feedpush(wrtag, bytes32(RAY), type(uint).max);
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(0));
        vm.expectRevert(UniNFTHook.ErrDir.selector);
        Vat(bank).frob(uilk, self, data, int(0));
    }

    function test_frob_down_five() public {
        uint160 onex96 = 2 ** 96;
        PoolArgs memory args = PoolArgs(
            Asset(agold, 1000 * WAD), Asset(WETH, 1000 * WAD),
            500, onex96, onex96 * 3 / 4, onex96 * 4 / 3, 10
        );
        uint[4] memory goldwethtokids;
        goldwethtokids[0] = goldwethtokid;
        nfpm.approve(bank, golddaitokid);
        for (uint i = 0; i < 4; i++) {
            (goldwethtokids[i],,,) = join_pool(args);
            nfpm.approve(bank, goldwethtokids[i]);
        }

        bytes memory data = abi.encodePacked(
            int(1), golddaitokid, goldwethtokids[0], goldwethtokids[1],
            goldwethtokids[2], goldwethtokids[3]
        );
        Vat(bank).frob(uilk, self, data, int(WAD));

        assertEq(nfpm.ownerOf(golddaitokid), bank);
        for (uint i = 0; i < 4; i++) {
            assertEq(nfpm.ownerOf(goldwethtokids[i]), bank);
        }

        data = abi.encodePacked(
            -int(1), golddaitokid, goldwethtokids[0], goldwethtokids[1],
            goldwethtokids[2], goldwethtokids[3]
        );
        rico_mint(100, true); // rounding
        Vat(bank).frob(uilk, self, data, -int(WAD));

        assertEq(nfpm.ownerOf(golddaitokid), self);
        for (uint i = 0; i < 4; i++) {
            assertEq(nfpm.ownerOf(goldwethtokids[i]), self);
        }

        nfpm.approve(bank, golddaitokid);
        for (uint i = 0; i < 4; i++) {
            nfpm.approve(bank, goldwethtokids[i]);
        }
        data = abi.encodePacked(
            int(1), golddaitokid, goldwethtokids[0], goldwethtokids[1],
            goldwethtokids[2], goldwethtokids[3]
        );
        Vat(bank).frob(uilk, self, data, int(WAD));

        data = abi.encodePacked(
            -int(1), golddaitokid, goldwethtokids[1], goldwethtokids[3]
        );
        Vat(bank).frob(uilk, self, data, -int(WAD));
    }

    function test_geth() public {
        assertEq(address(bytes20(Vat(bank).geth(uilk, 'nfpm', empty))), address(nfpm));
        assertEq(uint(Vat(bank).geth(uilk, 'ROOM', empty)), HOOK_ROOM);
        assertEq(address(bytes20(Vat(bank).geth(uilk, 'wrap', empty))), uniwrapper);
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'oh', empty);

        bytes32 val;
        val = Vat(bank).geth(uilk, 'fsrc', single(bytes32(bytes20(WETH))));
        assertEq(address(bytes20(val)), address(mdn));
        val = Vat(bank).geth(uilk, 'ftag', single(bytes32(bytes20(WETH))));
        assertEq(val, wrtag);

        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'oh', single(bytes32(bytes20(WETH))));

        // wrong xs length
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'oh', new bytes32[](2));
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).geth(uilk, 'fsrc', new bytes32[](0));
    }

    function test_filh() public {
        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'blah', empty, bytes32(bytes20(address(nfpm))));
        // wrong xs length
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'ROOM', new bytes32[](1), bytes32(uint(6)));

        Vat(bank).filh(uilk, 'ROOM', empty, bytes32(uint(5)));
        Vat(bank).filh(uilk, 'nfpm', empty, bytes32(bytes20(address(nfpm))));
        Vat(bank).filh(uilk, 'wrap', empty, bytes32(bytes20(self)));


        // wrong key
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'blah', single(bytes32(bytes20(self))), bytes32(uint(5)));
        // wrong xs length
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'fsrc', empty, bytes32(uint(5)));
        vm.expectRevert(Bank.ErrWrongKey.selector);
        Vat(bank).filh(uilk, 'fsrc', new bytes32[](2), bytes32(uint(5)));

        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(self))), bytes32(uint(10)));
        Vat(bank).filh(uilk, 'ftag', single(bytes32(bytes20(self))), bytes32(uint(100)));
    }

    function test_not_found() public {
        // add goldwethtokid and golddaitokid at once
        bytes memory data = abi.encodePacked(int(1), goldwethtokid);
        Vat(bank).frob(uilk, self, data, int(WAD));

        data = abi.encodePacked(-int(1), golddaitokid);
        vm.expectRevert(UniNFTHook.ErrNotFound.selector);
        Vat(bank).frob(uilk, self, data, -int(WAD/2));

        data = abi.encodePacked(-int(1), golddaitokid);
    }

    function test_no_feed() public {
        // weth feed null...frob should fail
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(WETH))), bytes32(uint(0)));
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(agold))), bytes32(bytes20(address(mdn))));
        vm.expectRevert();
        Vat(bank).frob(uilk, self, abi.encodePacked(int(1), goldwethtokid), int(WAD));

        // gold feed null...frob should fail
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(WETH))), bytes32(bytes20(address(mdn))));
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(agold))), bytes32(uint(0)));
        vm.expectRevert();
        Vat(bank).frob(uilk, self, abi.encodePacked(int(1), goldwethtokid), int(WAD));

        // both feeds non-null...frob should pass
        Vat(bank).filh(uilk, 'fsrc', single(bytes32(bytes20(agold))), bytes32(bytes20(address(mdn))));
        Vat(bank).frob(uilk, self, abi.encodePacked(int(1), goldwethtokid), int(WAD));
    }
}
