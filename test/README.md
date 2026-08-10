# Tests

Offline tests. They stub the 1.12 client API (`wow.lua`) so the addon can be
loaded and driven without WoW. Run from this directory with system Lua:

    lua smoke.lua        # loads the addon, fires events, runs every slash command
    lua collision.lua    # shared-icon buffs must NOT produce bars
    lua nosuperwow.lua   # same addon on a client without SuperWoW
    lua grow.lua         # which side extra bars stack towards, in both layouts
    lua preview.lua      # example shields shown while the options window is open
    lua g.lua            # name guard: spell id vs tooltip, fail-open, caching
    lua s.lua            # school parsed out of a potion's buff name
    lua o.lua            # absorb routing order

Note: system Lua is 5.4, the game is 5.0. `wow.lua` aliases `string.gfind`
and `table.getn` so 5.0-only idioms in the addon still run here. That means
these tests do NOT prove 5.0 compatibility — `luac -p ShieldBar.lua` plus
avoiding `gmatch`/`string.match`/`#t`/`select()` covers that.

These tests cannot verify anything the client owns: real icon paths, real
tooltip text, actual absorb values, or GUI layout. Those still need in-game
checks with `/sb debug`.
