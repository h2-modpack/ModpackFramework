local lu = require('luaunit')

TestMain = {}

function TestMain:testGetRendererIsSafeBeforeInit()
    local render = public.getRenderer("missing-pack")
    local ok = pcall(render)
    lu.assertTrue(ok)
end

function TestMain:testGetMenuBarIsSafeBeforeInit()
    local addMenuBar = public.getMenuBar("missing-pack")
    local ok = pcall(addMenuBar)
    lu.assertTrue(ok)
end
