-- =============================================================================
-- Run all Framework tests
-- =============================================================================
-- Usage: lua5.1 tests/all.lua (from the adamant-modpack-Framework directory)

require('tests/TestUtils')
require('tests/TestDiscovery')
require('tests/TestHash')

local lu = require('luaunit')
os.exit(lu.LuaUnit.run())
