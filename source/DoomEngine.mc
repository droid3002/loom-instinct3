//
// DOOM for Garmin Connect IQ - Instinct 3 Solar
// Game engine: tile-based raycasting renderer with a Doom feel.
// Everything is software rendered in Monkey C onto the 176x176 B&W display.
//
// Watchdog-safe design (firmware kills the UI thread if one callback runs
// too long, which looked like an instant "crash on launch"):
//  - all angles stored in RADIANS (Toybox.Math cos/sin take radians)
//  - DDA grid traversal: max ~32 grid crossings per ray instead of hundreds
//    of small ray-marching steps
//  - one ray per COLUMN_STEP screen columns, drawn as a 2px wide slice
//

using Toybox.Graphics as Gfx;
using Toybox.Math as Math;

const TILE_EMPTY = 0;
const TILE_WALL  = 1;
const TILE_DOOR  = 2;

const MAP_W = 16;
const MAP_H = 12;
// Screen reserves: the Instinct 3 draws its status ring over the top arc and
// the curved bezel clips the corners — text only survives near the bottom
// center of the panel.
const TOP_RES_Y = 34;     // 3D view starts below the ring arc
const BOT_RES_Y = 26;     // HUD text zone at the bottom

const _PI     = 3.14159265359;
const FOV_DEG = 60.0;
const MOVE_STEP = 0.20;    // tiles per key press
const RENDER_DIST = 16.0;  // max render distance (tiles)
const FOG_DIST  = 12.0;    // distance at which walls fade into white fog
const COLUMN_STEP   = 2;   // one ray per N screen columns
const MAX_DDA_STEPS = 32;  // hard cap of grid crossings per ray

class DoomEngine {
    var mMap;              // int[MAP_H][MAP_W]: 0 empty, 1 wall, 2 door
    var mPx = 0.0;         // player X
    var mPy = 0.0;         // player Y
    var mPa = 0.0;         // player heading, radians
    var mTurn = :none;     // :none | :left | :right  selected turn direction
    var mHealth = 100;
    var mAmmo = 50;
    var mEnemies;          // array of dicts: :x :y :alive

    function initialize() {
        mMap = [
            [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
            [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,1],
            [1,0,1,1,1,1,0,1,0,1,1,1,1,0,1,1],
            [1,0,1,0,0,0,0,1,0,0,0,0,0,0,1,1],
            [1,0,1,0,1,2,2,1,0,1,1,1,1,0,0,1],
            [1,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1],
            [1,1,1,1,1,0,1,1,1,1,1,0,0,0,0,1],
            [1,0,0,0,0,0,1,0,0,0,0,0,1,1,0,1],
            [1,0,1,1,1,0,0,0,1,1,1,0,1,0,0,1],
            [1,0,0,0,1,0,1,0,0,0,0,0,0,0,0,1],
            [1,0,0,0,0,0,0,0,1,1,1,1,1,0,0,1],
            [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
        ];
        mPx = 2.5;
        mPy = 1.5;   // row 1 is the open corridor; (2.5, 2.5) is inside a wall
        mPa = 0.0;
        mHealth = 100;
        mAmmo = 50;
        mEnemies = [
            { :x=>5.5,  :y=>1.5,   :alive=>true },
            { :x=>9.5,  :y=>5.5,   :alive=>true },
            { :x=>4.5,  :y=>10.5,  :alive=>true },
            { :x=>11.5, :y=>3.5,   :alive=>true },
            { :x=>3.5,  :y=>9.5,   :alive=>true },
            { :x=>13.5, :y=>9.5,   :alive=>true }
        ];
    }

    function getMap() { return mMap; }
    function getPx() { return mPx; }
    function getPy() { return mPy; }
    function getPa() { return mPa; }
    function getTurn() { return mTurn; }
    function getHealth() { return mHealth; }
    function getAmmo() { return mAmmo; }
    function getEnemies() { return mEnemies; }

    // BACK button: cycle the selected turn direction (shown at top of screen)
    function cycleTurn() {
        if (mTurn == :none) {
            mTurn = :left;
        } else if (mTurn == :left) {
            mTurn = :right;
        } else {
            mTurn = :none;
        }
    }

    // Turn by deg DEGREES (the view uses ±10)
    function turn(deg) {
        mPa = mPa + deg * _PI / 180.0;
        while (mPa < 0) { mPa = mPa + 2 * _PI; }
        while (mPa >= 2 * _PI) { mPa = mPa - 2 * _PI; }
    }

    function blocked(x, y) {
        // Math.floor() returns a Float; array access always uses Numbers.
        var mx = Math.floor(x).toNumber();
        var my = Math.floor(y).toNumber();
        if (mx < 0 || my < 0 || mx >= MAP_W || my >= MAP_H) {
            return true;
        }
        var tile = mMap[my][mx];
        return (tile == TILE_WALL || tile == TILE_DOOR);
    }

    function tryMove(dx, dy) {
        var r = 0.18;
        var nx = mPx + dx;
        var ny = mPy + dy;
        if (!blocked(nx - r, ny - r) &&
            !blocked(nx + r, ny - r) &&
            !blocked(nx - r, ny + r) &&
            !blocked(nx + r, ny + r)) {
            mPx = nx;
            mPy = ny;
        }
    }

    // UP button: move forward one step
    function moveForward() {
        tryMove(MOVE_STEP * Math.cos(mPa), MOVE_STEP * Math.sin(mPa));
    }

    // DOWN button (no turn selected): move backward one step
    function moveBack() {
        tryMove(-MOVE_STEP * Math.cos(mPa), -MOVE_STEP * Math.sin(mPa));
    }

    // LIGHT button (or long DOWN): toggle the door in front of the player
    function toggleDoor() {
        var tx = mPx + Math.cos(mPa) * 1.2;
        var ty = mPy + Math.sin(mPa) * 1.2;
        var mx = Math.floor(tx + 0.5).toNumber();
        var my = Math.floor(ty + 0.5).toNumber();
        if (mx >= 0 && my >= 0 && mx < MAP_W && my < MAP_H &&
            mMap[my][mx] == TILE_DOOR) {
            mMap[my][mx] = TILE_EMPTY;
        }
    }

    // SELECT/GPS button: hitscan shot along the player's heading
    function fire() {
        if (mAmmo > 0) {
            mAmmo = mAmmo - 1;
        }
        var dx = Math.cos(mPa);
        var dy = Math.sin(mPa);
        var dist = 0.0;
        var hit = false;
        var enemySize = 0.35;
        var i;
        var e;
        var tile;
        while (dist < 8.0 && !hit) {
            dist = dist + 0.15;
            var tx = mPx + dx * dist;
            var ty = mPy + dy * dist;
            var mx = Math.floor(tx).toNumber();
            var my = Math.floor(ty).toNumber();
            if (mx < 0 || my < 0 || mx >= MAP_W || my >= MAP_H) {
                break;
            }
            tile = mMap[my][mx];
            if (tile == TILE_WALL || tile == TILE_DOOR) {
                break;
            }
            for (i = 0; i < mEnemies.size(); i++) {
                e = mEnemies[i];
                if (e[:alive] != true) {
                    continue;
                }
                var ddx = tx - e[:x];
                var ddy = ty - e[:y];
                if ((ddx < 0 ? -ddx : ddx) < enemySize &&
                    (ddy < 0 ? -ddy : ddy) < enemySize) {
                    e[:alive] = false;
                    hit = true;
                    break;
                }
            }
        }
    }

    // Cast one DDA ray from the player. Returns the perpendicular wall
    // distance, or -1.0 when the ray leaves the room (open space).
    function castRay(rdx, rdy) {
        var mapX = Math.floor(mPx).toNumber();
        var mapY = Math.floor(mPy).toNumber();
        var deltaX = (rdx < 0 ? -rdx : rdx) > 1e-9 ? 1.0 / (rdx < 0 ? -rdx : rdx) : 3.0e9;
        var deltaY = (rdy < 0 ? -rdy : rdy) > 1e-9 ? 1.0 / (rdy < 0 ? -rdy : rdy) : 3.0e9;

        var stepX;
        var stepY;
        var sideX;
        var sideY;
        if (rdx < 0) {
            stepX = -1;
            sideX = (mPx - mapX) * deltaX;
        } else {
            stepX = 1;
            sideX = (mapX + 1.0 - mPx) * deltaX;
        }
        if (rdy < 0) {
            stepY = -1;
            sideY = (mPy - mapY) * deltaY;
        } else {
            stepY = 1;
            sideY = (mapY + 1.0 - mPy) * deltaY;
        }

        var tile = TILE_EMPTY;
        var side = 0;
        var guard = 0;
        while (guard < MAX_DDA_STEPS && tile == TILE_EMPTY) {
            guard = guard + 1;
            if (sideX < sideY) {
                sideX = sideX + deltaX;
                mapX = mapX + stepX;
                side = 0;
            } else {
                sideY = sideY + deltaY;
                mapY = mapY + stepY;
                side = 1;
            }
            if (mapX < 0 || mapY < 0 || mapX >= MAP_W || mapY >= MAP_H) {
                return -1.0;
            }
            tile = mMap[mapY][mapX];
        }
        if (tile == TILE_EMPTY) {
            return -1.0;
        }
        // Perpendicular distance so walls don't fisheye
        if (side == 0) {
            return sideX - deltaX;
        }
        return sideY - deltaY;
    }

    // Draw the 3D world (raycast walls), COLUMN_STEP screen columns per ray.
    function render(dc, viewX, viewY, viewW, viewH) {
        var fovRad = FOV_DEG * _PI / 180.0;
        var cx = 0;
        var castCount = 0;
        while (cx < viewW) {
            var cameraX = 2.0 * cx / viewW - 1.0;
            var rayA = mPa + cameraX * fovRad / 2.0;
            var perp = castRay(Math.cos(rayA), Math.sin(rayA));
            if (perp > 0.0 && perp <= FOG_DIST) {
                if (perp < 0.2) {
                    perp = 0.2;
                }
                var lineHeight = (viewH * 0.9) / perp;
                if (lineHeight > viewH * 2.5) {
                    lineHeight = viewH * 2.5;
                }
                var yStart = Math.floor(viewY + (viewH - lineHeight) / 2).toNumber();
                var yEnd = Math.floor(yStart + lineHeight).toNumber();
                if (yStart < viewY) {
                    yStart = viewY;
                }
                if (yEnd > viewY + viewH) {
                    yEnd = viewY + viewH;
                }
                // Distance shading: solid up close, checkerboard dither for
                // mid-range walls, sparse dots near the fog edge.
                drawShadedColumn(dc, viewX + cx, viewX + cx + 1,
                    yStart, yEnd, 1.0 - perp / FOG_DIST, castCount);
                castCount = castCount + 1;
            }
            cx = cx + COLUMN_STEP;
        }
    }

    // One 2px screen column of wall: shading level from shade (1=near,
    // 0=fog). colIdx alternates the checker phase between columns.
    function drawShadedColumn(dc, cx, x2, yStart, yEnd, shade, colIdx) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
        if (shade > 0.60) {
            dc.fillRectangle(cx, yStart, 2, yEnd - yStart + 1);
            return;
        }
        var step = (shade > 0.25) ? 6 : 12;
        var thick = (shade > 0.25) ? 2 : 1;
        var y = yStart + (colIdx % 2) * ((step / 2).toNumber());
        while (y + thick <= yEnd + 1) {
            dc.fillRectangle(cx, y, 2, thick);
            y = y + step;
        }
    }

    // Draw enemies as black sprites with two white eye pixels. Occluded
    // sprites (wall between player and enemy) are not drawn.
    function renderSprites(dc, viewX, viewY, viewW, viewH) {
        var halfW = viewW / 2;
        var fovRad = FOV_DEG * _PI / 180.0;
        var halfFov = fovRad / 2;
        var i;
        var e;
        var dx;
        var dy;
        var dist;
        var rel;
        var screenX;
        var spriteH;
        var spriteW;
        var x0;
        var y0;
        var x1;
        var y1;
        var wallDist;
        var eyeY;
        for (i = 0; i < mEnemies.size(); i++) {
            e = mEnemies[i];
            if (e[:alive] != true) {
                continue;
            }
            dx = e[:x] - mPx;
            dy = e[:y] - mPy;
            dist = Math.sqrt(dx * dx + dy * dy);
            if (dist > FOG_DIST) {
                continue;
            }
            // atan2 returns radians; mPa is radians now
            rel = Math.atan2(dy, dx) - mPa;
            while (rel > _PI) { rel = rel - 2 * _PI; }
            while (rel < -_PI) { rel = rel + 2 * _PI; }
            // abs(rel) <= half field of view (parentheses matter!)
            if ((rel < 0 ? -rel : rel) > halfFov) {
                continue;
            }
            // Occlusion: skip the sprite if a wall blocks the line of sight.
            wallDist = castRay(dx / dist, dy / dist);
            if (wallDist >= 0.0 && wallDist < dist - 0.25) {
                continue;
            }
            screenX = viewX + halfW + (rel / halfFov) * halfW;
            spriteH = (viewH * 0.8) / dist;
            spriteW = spriteH * 0.6;
            if (spriteW < 2) { spriteW = 2; }
            if (spriteH < 2) { spriteH = 2; }
            if (spriteH > viewH) { spriteH = viewH.toNumber(); }
            x0 = Math.floor(screenX - spriteW / 2).toNumber();
            y0 = Math.floor(viewY + viewH / 2 - spriteH / 2).toNumber();
            x1 = Math.floor(screenX + spriteW / 2).toNumber();
            y1 = Math.floor(viewY + viewH / 2 + spriteH / 2).toNumber();
            if (x0 < viewX) { x0 = viewX; }
            if (y0 < viewY) { y0 = viewY; }
            if (x1 > viewX + viewW) { x1 = viewX + viewW; }
            if (y1 > viewY + viewH) { y1 = viewY + viewH; }
            if (x1 - x0 < 1 || y1 - y0 < 1) {
                continue;
            }
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
            // Solid silhouette (readable against dithered walls); farther
            // imps get white stripes — a "fade" without losing the outline.
            dc.fillRectangle(x0, y0, x1 - x0, y1 - y0);
            if (dist > 4.0 && (x1 - x0) > 3 && (y1 - y0) > 7) {
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
                var yy = y0 + 2;
                while (yy < y1 - 3) {
                    dc.fillRectangle(x0 + 1, yy, (x1 - x0) - 2, 1);
                    yy = yy + 5;
                }
            }
            // Two white eye pixels, at ~1/4 height, 1/3 apart horizontally.
            if (y1 - y0 > 5) {
                eyeY = y0 + (y1 - y0) / 4;
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
                dc.fillRectangle(x0 + (x1 - x0) / 3, eyeY,
                    (x1 - x0) > 6 ? 2 : 1, (y1 - y0) > 14 ? 2 : 1);
                dc.fillRectangle(x0 + (x1 - x0) * 2 / 3, eyeY,
                    (x1 - x0) > 6 ? 2 : 1, (y1 - y0) > 14 ? 2 : 1);
            }
        }
    }
}
