// SPDX-License-Identifier: AGPL-3.0-or-later

/// vat.sol -- Dai CDP database

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.6;

// FIXME: This contract was altered compared to the production version.
// It doesn't use LibNote anymore.
// New deployments of this contract will need to include custom events (TO DO).

import './mixin/math.sol';
import './mixin/ward.sol';

contract Vat is Math, Ward {
    // --- Data ---
    struct Ilk {
        uint256 Art;   // Total Normalised Debt     [wad]
        uint256 rack;  // Accumulated Rate          [ray]

        uint256 mark;  // Last poked price          [ray]

        uint256 liqr;  // Liquidation Ratio         [ray]
        uint256 chop;  // Liquidation Penalty       [ray]

        uint256 line;  // Debt Ceiling              [rad]
        uint256 dust;  // Urn Debt Floor            [rad]

        uint256 duty;  // Collateral-specific, per-second compounding rate [ray]
        uint256  rho;  // Time of last drip [unix epoch time]

        bool    open;  // Don't require ACL
    }

    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }

    mapping (bytes32 => Ilk)                       public ilks;
    mapping (bytes32 => mapping (address => Urn )) public urns;
    mapping (bytes32 => mapping (address => uint)) public gem;  // [wad]
    mapping (address => uint256)                   public dai;  // [rad]
    mapping (address => uint256)                   public sin;  // [rad]

    uint256 public debt;  // Total Dai Issued    [rad]
    uint256 public vice;  // Total Unbacked Dai  [rad]
    uint256 public Line;  // Total Debt Ceiling  [rad]
    bool    public live;  // Active Flag


    uint256 public par;   // System Price (dai/ref)        [wad]
    uint256 public way;   // System Rate (SP growth rate)  [ray]
    uint256 public tau;   // Last prod

    address public vow;   // Debt/surplus auction house

    // --- Init ---
    constructor() {
        live = true;
        par = RAY;
        way = RAY;
    }

    // --- Administration ---
    function init(bytes32 ilk) external auth {
        require(ilks[ilk].rack == 0, "Vat/ilk-already-init");
        ilks[ilk] = Ilk({
            rack: RAY,
            duty: RAY,
            liqr: RAY,
            open: true, // TODO consider defaults
            rho : time(),
            Art: 0, mark: 0, chop: 0, line: 0, dust: 0
        });
    }

    function cage() external auth {
        live = false;
    }

    // --- Fungibility ---
    function slip(bytes32 ilk, address usr, int256 wad) external auth {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        require(wish(src, msg.sender), "Vat/not-allowed");
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function move(address src, address dst, uint256 rad) external {
        require(wish(src, msg.sender), "Vat/not-allowed");
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }

    function lock(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, int(amt), 0);
    }
    function free(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, -int(amt), 0);
    }
    function draw(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, 0, int(amt));
    }
    function wipe(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, 0, -int(amt));
    }

    // --- CDP Manipulation ---
    function frob(bytes32 i, address u, address v, address w, int dink, int dart) public {
        // TODO drip?
        // TODO prod?
        Urn memory urn = urns[i][u];
        Ilk memory ilk = ilks[i];

        require(ilk.open || acl[i][msg.sender], 'err-acl');

        // ilk has been initialised
        require(ilk.rack != 0, "Vat/ilk-not-init");

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.Art = add(ilk.Art, dart);

        int dtab = mul(ilk.rack, dart);
        uint tab = mul(ilk.rack, urn.art);
        debt     = add(debt, dtab);

        // either debt has decreased, or debt ceilings are not exceeded
        require(either(dart <= 0, both(mul(ilk.Art, ilk.rack) <= ilk.line, debt <= Line)), "Vat/ceiling-exceeded");
        // urn is either less risky than before, or it is safe
        require(either(both(dart <= 0, dink >= 0), safe(i, u)), "Vat/not-safe");

        // urn is either more safe, or the owner consents
        require(either(both(dart <= 0, dink >= 0), wish(u, msg.sender)), "Vat/not-allowed-u");
        // collateral src consents
        require(either(dink <= 0, wish(v, msg.sender)), "Vat/not-allowed-v");
        // debt dst consents
        require(either(dart >= 0, wish(w, msg.sender)), "Vat/not-allowed-w");

        // urn has no debt, or a non-dusty amount
        require(either(urn.art == 0, tab >= ilk.dust), "Vat/dust");

        gem[i][v] = sub(gem[i][v], dink);
        dai[w]    = add(dai[w],    dtab);

        urns[i][u] = urn;
        ilks[i]    = ilk;
    }

    // --- CDP Fungibility ---
    function fork(bytes32 ilk, address src, address dst, int dink, int dart) external {
        // TODO drip?
        // TODO prod?
        Urn storage u = urns[ilk][src];
        Urn storage v = urns[ilk][dst];
        Ilk storage i = ilks[ilk];

        require(i.open || acl[ilk][msg.sender], 'err-acl');

        u.ink = sub(u.ink, dink);
        u.art = sub(u.art, dart);
        v.ink = add(v.ink, dink);
        v.art = add(v.art, dart);

        uint utab = mul(u.art, i.rack);
        uint vtab = mul(v.art, i.rack);

        // both sides consent
        require(both(wish(src, msg.sender), wish(dst, msg.sender)), "Vat/not-allowed");

        // both sides safe
        require(safe(ilk, src), "Vat/not-safe-src");
        require(safe(ilk, dst), "Vat/not-safe-dst");

        // both sides non-dusty
        require(either(utab >= i.dust, u.art == 0), "Vat/dust-src");
        require(either(vtab >= i.dust, v.art == 0), "Vat/dust-dst");
    }

    // --- CDP Confiscation ---
    function grab(bytes32 i, address u, address v, address w, int dink, int dart) external auth {
        // TODO acl?
        // TODO drip?
        // TODO prod?
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.Art = add(ilk.Art, dart);

        int dtab = mul(ilk.rack, dart);

        gem[i][v] = sub(gem[i][v], dink);
        sin[w]    = sub(sin[w],    dtab);
        vice      = sub(vice,      dtab);
    }

    // --- Settlement ---
    function heal(uint rad) external {
        address u = msg.sender;
        sin[u] = sub(sin[u], rad);
        dai[u] = sub(dai[u], rad);
        vice   = sub(vice,   rad);
        debt   = sub(debt,   rad);
    }
    function suck(address u, address v, uint rad) external auth {
        sin[u] = add(sin[u], rad);
        dai[v] = add(dai[v], rad);
        vice   = add(vice,   rad);
        debt   = add(debt,   rad);
    }

    function owed(bytes32 i, address u) public returns (uint256 rad) {
      drip(i);
      return mul(ilks[i].rack, urns[i][u].art);
    }
    function rowed(bytes32 i, address u) public returns (uint256 ray) {
      return owed(i, u) / WAD;
    }
    function wowed(bytes32 i, address u) public returns (uint256 wad) {
      return owed(i, u) / RAY;
    }


    // --- Rates ---
    function sway(uint256 r) external auth {
        prod();
        way = r;
    }

    function drip(bytes32 i) public {
        Ilk storage ilk = ilks[i];
        if (time() == ilk.rho) return;
        require(time() >= ilk.rho, 'Vat/invalid-now');
        uint256 prev = ilk.rack;
        uint256 rack = grow(prev, ilk.duty, time() - ilk.rho);
        int256  delt = diff(rack, prev);
        int256  rad  = mul(ilk.Art, delt);
        ilk.rack     = add(ilk.rack, delt);
        dai[vow]     = add(dai[vow], rad);
        debt         = add(debt, rad);
    }
    function prod() public {
        if (time() == tau) return;
        par = grow(par, way, time() - tau);
        tau = time();
    }

    function file_Line(uint Line_) external auth {
        Line = Line_;
    }
    function file_vow(address vow_) external auth {
        vow = vow_;
    }
    function file_line(bytes32 i, uint line) external auth {
        ilks[i].line = line;
    }
    function file_dust(bytes32 i, uint dust) external auth {
        ilks[i].dust = dust;
    }
    // TODO file_duty might be special considering drip requirement
    function file_duty(bytes32 i, uint duty) external auth {
        drip(i);
        ilks[i].duty = duty;
    }

    function file_open(bytes32 i, bool open) external auth {
        ilks[i].open = open;
    }
    function file_acl(bytes32 i, address u, bool bit) external auth {
        acl[i][u] = bit;
    }

    function time() public view returns (uint256) {
        return block.timestamp;
    }

    function jam_par(uint256 jam) external auth {
        par = jam;
    }

    // TODO force `spot` value without loss of precision  ?
    //function jam_spot

    function safe(bytes32 i, address u) public returns (bool) {
        prod();
        drip(i);
        Urn memory urn = urns[i][u];
        Ilk memory ilk = ilks[i];
        uint256    ref = rmul(par, ilk.mark);
        uint256    liq = rmul(ref, ilk.liqr);
        uint256    tab = mul(urn.art, ilk.rack);
        uint256    cut = mul(urn.ink, liq);
        return (tab <= cut);
    }

    function plot(bytes32 ilk, uint mark) external auth {
        ilks[ilk].mark = mark;
    }

    mapping (bytes32 => mapping (address => bool)) public acl;

    mapping (address => mapping (address => bool)) public can;
    function hope(address usr) external {
        can[msg.sender][usr] = true;
    }
    function nope(address usr) external {
        can[msg.sender][usr] = false;
    }
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == true);
    }

}
