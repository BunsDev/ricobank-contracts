/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.19;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {DutchFlower} from './flow.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Ward} from "../lib/feedbase/src/mixin/ward.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter, IUniWrapper} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Math} from '../src/mixin/math.sol';
import {ERC20Hook} from './hook/ERC20hook.sol';
import {UniNFTHook, DutchNFTFlower} from './hook/nfpm/UniV3NFTHook.sol';
import {Ploker} from './test/Ploker.sol';

contract Ball is Math, Ward {
    bytes32 internal constant RICO_DAI_TAG = "rico:dai";
    bytes32 internal constant DAI_RICO_TAG = "dai:rico";
    bytes32 internal constant XAU_USD_TAG = "xau:usd";
    bytes32 internal constant DAI_USD_TAG = "dai:usd";
    bytes32 internal constant RICO_XAU_TAG = "rico:xau";
    bytes32 internal constant RICO_REF_TAG = "rico:ref";
    bytes32 internal constant RICO_RISK_TAG  = "rico:risk";
    bytes32 internal constant RISK_RICO_TAG  = "risk:rico";

    DutchFlower public flow;
    Vat public vat;
    Vow public vow;
    Vox public vox;
    ERC20Hook public hook;
    UniNFTHook public nfthook;
    DutchNFTFlower public nftflow;
    address public feedbase;

    Medianizer public mdn;
    UniswapV3Adapter public uniadapt;
    Divider public divider;
    ChainlinkAdapter public cladapt;
   
    struct IlkParams {
        bytes32 ilk;
        address gem;
        address pool;
        uint    chop;
        uint    dust;
        uint    fee;
        uint    line;
        uint    liqr;
        DutchFlower.Ramp ramp;
        uint    ttl;
        uint    range;
    }

    struct UniParams {
        address nfpm;
        bytes32 ilk;
        uint fee;
        uint gain;
        uint fuel;
        uint fade;
        uint chop;
        uint room;
        address uniwrapper;
    }

    struct BallArgs {
        address feedbase;
        address rico;
        address risk;
        address ricodai;
        address ricorisk;
        address router;
        address uniwrapper;
        uint    par;
        uint    ceil;
        uint    adaptrange;
        uint    adaptttl;
        uint    daiusdttl;
        uint    xauusdttl;
        DutchFlower.Ramp ricoramp;
        DutchFlower.Ramp riskramp;
        Vow.Ramp         mintramp;
        address DAI;
        address DAI_USD_AGG;
        address XAU_USD_AGG;
    }

    address public rico;
    address public risk;
    address public dai;

    Ploker public ploker;

    constructor(
        BallArgs    memory args
    ) payable {
        rico = args.rico;
        risk = args.risk;
        dai = args.DAI;
        feedbase = args.feedbase;

        flow = new DutchFlower();
        vat  = new Vat();
        vow  = new Vow();
        hook = new ERC20Hook(feedbase, address(vat), address(flow), rico);
        mdn = new Medianizer(feedbase);
        uniadapt = new UniswapV3Adapter(Feedbase(feedbase), IUniWrapper(args.uniwrapper));
        cladapt = new ChainlinkAdapter(feedbase);
        divider = new Divider(feedbase, RAY);
        ploker = new Ploker();

        vat.prod(args.par);

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vat.file('ceil',  args.ceil);
        vat.link('rico',  rico);
        vow.ward(address(flow), true);
        vat.ward(address(vow), true);
        hook.ward(address(flow), true); // flowback
        hook.ward(address(vat), true);  // grabhook, frobhook

        // todo ramp config
        vow.pair(risk, "fade", args.riskramp.fade);
        vow.pair(risk, "tiny", args.riskramp.tiny);
        vow.pair(risk, "fuel", args.riskramp.fuel);
        vow.pair(risk, "gain", args.riskramp.gain);
        vow.pair(risk, "feed", uint(uint160(feedbase)));
        vow.pair(risk, "fsrc", uint(uint160(bytes20(address(mdn)))));
        vow.pair(risk, "ftag", uint(RISK_RICO_TAG));
        vow.file("vel", args.mintramp.vel);
        vow.file("rel", args.mintramp.vel);
        vow.file("bel", args.mintramp.bel);
        vow.file("cel", args.mintramp.cel);

        vow.pair(rico, "fade", args.ricoramp.fade);
        vow.pair(rico, "tiny", args.ricoramp.tiny);
        vow.pair(rico, "fuel", args.ricoramp.fuel);
        vow.pair(rico, "gain", args.ricoramp.gain);
        vow.pair(rico, "feed", uint(uint160(feedbase)));
        vow.pair(rico, "fsrc", uint(uint160(address(mdn))));
        vow.pair(rico, "ftag", uint(RICO_RISK_TAG));

        vow.grant(rico);
        vow.grant(risk);

        // rico/dai, dai/rico (== 1 / (rico/dai))
        uniadapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.adaptrange, args.adaptttl, args.DAI < rico)
        );
        {
            address[] memory sources = new address[](2);
            bytes32[] memory tags    = new bytes32[](2);
            Feedbase(feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
            sources[0] = address(this); tags[0] = bytes32("ONE");
            sources[1] = address(uniadapt); tags[1] = RICO_DAI_TAG;
            divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags));
        }

        //
        // rico/ref
        //
        cladapt.setConfig(
            XAU_USD_TAG, ChainlinkAdapter.Config(args.XAU_USD_AGG, args.xauusdttl, RAY)
        );
        cladapt.setConfig(
            DAI_USD_TAG, ChainlinkAdapter.Config(args.DAI_USD_AGG, args.daiusdttl, RAY)
        );
        {
            address[] memory src3 = new address[](3);
            bytes32[] memory tag3 = new bytes32[](3);
            src3[0] = address(cladapt); tag3[0] = DAI_USD_TAG;
            src3[1] = address(divider); tag3[1] = DAI_RICO_TAG;
            src3[2] = address(cladapt); tag3[2] = XAU_USD_TAG;
            divider.setConfig(RICO_XAU_TAG, Divider.Config(src3, tag3));
        }
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = RICO_XAU_TAG;
        mdnconf.quorum  = 1;
        mdn.setConfig(RICO_REF_TAG, mdnconf);
        // need four plokers: rico/ref, rico/risk, risk/rico, collateral/rico
        Ploker.Config memory plokerconf = Ploker.Config(
            new address[](3), new bytes32[](3), new address[](1), new bytes32[](1)
        );
        plokerconf.adapters[0] = address(cladapt); plokerconf.adaptertags[0] = XAU_USD_TAG;
        plokerconf.adapters[1] = address(cladapt); plokerconf.adaptertags[1] = DAI_USD_TAG;
        plokerconf.adapters[2] = address(uniadapt); plokerconf.adaptertags[2] = RICO_DAI_TAG;
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RICO_REF_TAG;
        ploker.setConfig(RICO_REF_TAG, plokerconf);
        ploker.setConfig(RICO_XAU_TAG, plokerconf);

        //
        // rico/risk, risk/rico
        //
        uniadapt.setConfig(
            RICO_RISK_TAG,
            UniswapV3Adapter.Config(args.ricorisk, args.adaptrange, args.adaptttl, rico < risk)
        );
        {
            address[] memory src2 = new address[](2);
            bytes32[] memory tag2 = new bytes32[](2);
            src2[0] = address(this); tag2[0] = bytes32("ONE");
            src2[1] = address(uniadapt); tag2[1] = RICO_RISK_TAG;
            divider.setConfig(RISK_RICO_TAG, Divider.Config(src2, tag2));
        }
        mdnconf.srcs[0] = address(uniadapt);
        mdnconf.tags[0] = RICO_RISK_TAG;
        mdn.setConfig(RICO_RISK_TAG, mdnconf);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = RISK_RICO_TAG;
        mdn.setConfig(RISK_RICO_TAG, mdnconf);
        plokerconf = Ploker.Config(
            new address[](1), new bytes32[](1), new address[](0), new bytes32[](0)
        );
        plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_RISK_TAG;
        ploker.setConfig(RICO_RISK_TAG, plokerconf);
        ploker.setConfig(RISK_RICO_TAG, plokerconf);


        cladapt.look(XAU_USD_TAG);
        (bytes32 ref,) = Feedbase(feedbase).pull(address(cladapt), XAU_USD_TAG);
        vox = new Vox(uint256(ref));
        vox.link('fb',  feedbase);
        vox.link('vat', address(vat));
        vox.link('tip', address(mdn));
        vox.file('tag', RICO_REF_TAG);
        vat.ward(address(vox), true);
    }

    function makeilk(IlkParams memory ilkparams) _ward_ public {
        bytes32 ilk = ilkparams.ilk;
        bytes32 ilkrico = concat(ilk, ':rico');
        vat.init(ilk, address(hook));
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = ilkrico;
        mdn.setConfig(ilkrico, mdnconf);
        hook.wire(ilk, ilkparams.gem, address(mdn), ilkrico);
        hook.grant(ilkparams.gem);
        vat.filk(ilk, 'chop', ilkparams.chop);
        vat.filk(ilk, 'dust', ilkparams.dust);
        vat.filk(ilk, 'fee',  ilkparams.fee);  // 5%
        vat.filk(ilk, 'line', ilkparams.line);
        vat.filk(ilk, 'liqr', ilkparams.liqr);
        hook.list(ilkparams.gem, true);

        address[] memory ss = new address[](2);
        bytes32[] memory ts = new bytes32[](2);
        if (ilkparams.gem == dai) {
            ss[0] = address(this); ts[0] = bytes32("ONE");

            // not using second uni adapter here, it's just dai/dai
            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](1), new bytes32[](1), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_DAI_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = ilkrico;
            ploker.setConfig(ilkrico, plokerconf);
        } else {
            bytes32 tag = concat(ilk, ':dai');
            uniadapt.setConfig(
                tag,
                UniswapV3Adapter.Config(
                    ilkparams.pool, ilkparams.range, ilkparams.ttl, ilkparams.gem > dai
                )
            );
            ss[0] = address(uniadapt); ts[0] = tag;

            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](2), new bytes32[](2), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = tag;
            plokerconf.adapters[1] = address(uniadapt); plokerconf.adaptertags[1] = RICO_DAI_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = ilkrico;
            ploker.setConfig(ilkrico, plokerconf);
        }

        ss[1] = address(uniadapt); ts[1] = RICO_DAI_TAG;
        divider.setConfig(ilkrico, Divider.Config(ss, ts));

        hook.pair(ilkparams.gem, "fade", ilkparams.ramp.fade);
        hook.pair(ilkparams.gem, "tiny", ilkparams.ramp.tiny);
        hook.pair(ilkparams.gem, "fuel", ilkparams.ramp.fuel);
        hook.pair(ilkparams.gem, 'gain', ilkparams.ramp.gain);
    }

    function makeuni(UniParams memory ups) _ward_ public {
        if (address(nftflow) != address(0)) return;
        // initialize uni ilk
        nftflow = new DutchNFTFlower(ups.nfpm, rico);
        nfthook = new UniNFTHook(feedbase, address(nftflow), rico, ups.nfpm, ups.room, ups.uniwrapper);
        vat.init(':uninft', address(nfthook));
        vat.filk(':uninft', 'fee', ups.fee);
        vat.filk(':uninft', 'chop', ups.chop);
        nfthook.pair('gain', ups.gain);
        nfthook.pair('fuel', ups.fuel);
        nfthook.pair('fade', ups.fade);

        nfthook.ward(address(nftflow), true);
        nfthook.ward(address(vat), true);
    }

    function approve(address usr) _ward_ public {
        mdn.give(usr);
        divider.give(usr);
        uniadapt.give(usr);
        cladapt.give(usr);
        ploker.give(usr);

        hook.give(usr);
        nfthook.give(usr);

        vow.give(usr);
        vat.give(usr);
        vox.give(usr);
    }

    function concat(bytes32 a, bytes32 b) internal pure returns (bytes32 res) {
        uint i;
        while (true) {
            if (a[i] == 0) break;
            unchecked{ i++; }
        }
        res = a | (b >> (i << 3));
    }
}
