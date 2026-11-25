_G = {}

local Compiler = require("./complier")
luteapi_luau = require("@lute/luau")
luteapi_process = require("@lute/process")
luteapi_net = require("@lute/net/client")
luteapi_server = require("@lute/net/server")
luteapi_fs = require("@lute/fs")
stdapi_json = require("@std/json")
luteapi_io = require("@lute/io")
local argsofapp = {...}

local Config = {
    Debug = false,
    ExportToLua = nil,
    Robloxluau = false,
    Input = argsofapp[2]
}

local i = 3

while i <= #argsofapp do
    local value = argsofapp[i]

    if value == "--debug" then
        Config.Debug = true

    elseif value == "--robloxluau" then
        Config.Robloxluau = true

    elseif value == "--exporttoluau" then
        Config.ExportToLua = argsofapp[i + 1]

        if not Config.ExportToLua then
            error("--exporttoluau requires an output filename")
        end

        i += 1
    end

    i += 1
end


if not Config.Input then
    print("Usages:")
    print("diamond <diamond file path> ")
    print("diamond <diamond file path> --debug > debuging the code ____workflow")
    print("diamond <diamond file path> --exporttoluau > export to luau code without runing")
    print("diamond <diamond file path> --robloxluau > chaning the system to worked in roblox system")
    return
end

local file = luteapi_fs.open(Config.Input, "r")
local source = luteapi_fs.read(file)
if Config.Debug then
    print(source)
end
luteapi_fs.close(file)
local highglobalvars = {}
if Config.Debug then
    print("Compling the Code...")
end
local ast = Compiler.Parse(source)

local function DebugTable(tbl, indent)
    indent = indent or 0

    local spaces = string.rep(" ", indent)

    print(spaces .. "{")

    for k, v in pairs(tbl) do
        local key

        if type(k) == "string" then
            key = "['" .. k .. "']"
        else
            key = "[" .. tostring(k) .. "]"
        end

        if type(v) == "table" then
            print(string.rep(" ", indent + 4) .. key .. "=")
            DebugTable(v, indent + 4)
        else
            local value = type(v) == "string"
                and ("'" .. v .. "'")
                or tostring(v)

            print(string.rep(" ", indent + 4) .. key .. "=" .. value .. ",")
        end
    end

    print(spaces .. "}")
end
if Config.Debug then
    DebugTable(ast)
end
local function CompileExpression(expr)
    local output = ""
    if not expr then
        return "nil"
    end

    local t = expr.type

    if t == "Identifier" then
        local name = expr.name or expr.raw

        if highglobalvars[name] then
            return "_G." .. name
        end

        return name
    elseif t == "IndexExpression" then
        return CompileExpression(expr.object)
            .. "["
            .. CompileExpression(expr.index)
            .. "]"

    elseif t == "MemberExpression" then
        return CompileExpression(expr.object)
            .. "."
            .. expr.property

    elseif t == "BinaryExpression" then
        local op = expr.operator

        if op == "!=" then
            op = "~="
        end

        return "(" .. CompileExpression(expr.left)
            .. " " .. op .. " " ..
            CompileExpression(expr.right) .. ")"

    elseif t == "UnaryExpression" then
        return expr.operator .. CompileExpression(expr.operand or expr.argument)
    elseif t == "NumberLiteral" or t == "Number" then
        return expr.raw or tostring(expr.value)

    elseif t == "StringLiteral" or t == "String" then
        return expr.raw or string.format("%q", expr.value)

    elseif t == "BooleanLiteral" or t == "Boolean" then
        return tostring(expr.value)

    elseif t == "NullLiteral" or t == "Null" then
        return "nil"

    elseif t == "CallExpression" or t == "Call" then
        local output = CompileExpression(expr.callee) .. "("

        for i, arg in ipairs(expr.arguments or {}) do
            if i > 1 then
                output = output .. ","
            end

            output = output .. CompileExpression(arg)
        end

        return output .. ")"
elseif t == "ParenthesizedExpression" then
    return "(" .. CompileExpression(expr.expression) .. ")"
elseif t == "FunctionExpression" then
    local output = "function("

    for i, param in ipairs(expr.parameters or {}) do
        if i > 1 then
            output = output .. ","
        end

        output = output .. param.name
    end

    if expr.vararg then
        if #(expr.parameters or {}) > 0 then
            output = output .. ","
        end

        output = output .. "..."
    end

    output = output .. ")"

    for _, body in ipairs(expr.body or {}) do
        output = output .. ____workflow(body)
    end

    return output .. " end"
elseif t == "MethodCallExpression" then
    local output = CompileExpression(expr.receiver)
        .. ":"
        .. expr.method
        .. "("

    for i, arg in ipairs(expr.arguments or {}) do
        if i > 1 then
            output = output .. ","
        end

        output = output .. CompileExpression(arg)
    end

    return output .. ")"
    elseif t == "TableConstructor" then
        local output = "{"

        for i, field in ipairs(expr.fields or {}) do
            if i > 1 then
                output = output .. ","
            end

            if field.type == "TableArrayField" then
                output = output .. CompileExpression(field.value)

            elseif field.type == "TableNameField" then
                output = output
                    .. field.name
                    .. "="
                    .. CompileExpression(field.value)

            elseif field.type == "TableKeyField" then
                output = output
                    .. "["
                    .. CompileExpression(field.key)
                    .. "]="
                    .. CompileExpression(field.value)
            elseif field.type == "TableIndexField" then
                output = output
                    .. "["
                    .. CompileExpression(field.key)
                    .. "]="
                    .. CompileExpression(field.value)
            else
                error("Unknown table field type: " .. tostring(field.type))
            end
        end

        return output .. "}"
    end

    if expr.raw then
        return expr.raw
    end

    error("Unknown expression type: " .. tostring(t))
end
local codeoutput = "pi=math.pi;function thread(...)return spawn(...)end function tfind(...)return table.find(...)end function append(...)table.append(...)end function insert(...)table.insert(...)end function pn(...)print(...)end function wn(...)warn(...)end function fo(...)info(...)end function er(...)error(...)end function len(item)return #item end function rad(deg)return math.rad(deg)end function deg(rad)return math.deg(rad)end function cos(deg)return math.cos(math.rad(deg))end function sin(deg)return math.sin(math.rad(deg))end function readfile(filepath)local file=luteapi_fs.open(filepath,'r')local code=luteapi_fs.read(file)luteapi_fs.close(file)return code end function writefile(filepath,code)local file=luteapi_fs.open(filepath,'w')luteapi_fs.write(file,code)luteapi_fs.close(file)end function request(...)return luteapi_net.request(...)end function runcmd(...)return luteapi_process.system(...)end function json_decode(...)return stdapi_json.deserialize(...)end function json_encode(tab)return stdapi_json.serialize(tab, true)end function tostr(...)return tostring(...)end function tonum(...)return tonumber(...)end function floor(...)return math.floor(...)end function round(...)return math.round(...)end function clamp(...)return math.clamp(...)end function runtest(...)return pcall(...)end function addpn(...)luteapi_io.write(...)end function input(str)luteapi_io.write(str or '')return luteapi_io.read()end function runluau(...)return luteapi_luau.load(luteapi_luau.compile(...),'@Luau')() end function wait(mis)local start=os.clock()while os.clock()-start<(mis/1000)do end end function unixtime()return os.time()+(os.clock()%1)end\n"
if Config.Robloxluau then
    codeoutput = "pi=math.pi;function thread(...)return spawn(...)end function tfind(...)return table.find(...)end function append(...)table.append(...)end function insert(...)table.insert(...)end function pn(...)print(...)end function wn(...)warn(...)end function fo(...)info(...)end function er(...)error(...)end function len(item)return #item end function rad(deg)return math.rad(deg)end function deg(rad)return math.deg(rad)end function cos(deg)return math.cos(math.rad(deg))end function sin(deg)return math.sin(math.rad(deg))end function tostr(...)return tostring(...)end function tonum(...)return tonumber(...)end function floor(...)return math.floor(...)end function round(...)return math.round(...)end function clamp(...)return math.clamp(...)end function runtest(...)return pcall(...)end function runluau(...)return loadstring(...)() end\n"
end
function ____workflow(line) 
    local output = ""
    local opcode = line.type
    if opcode == "VariableDeclaration" then
        local v1 = "local "
        if line.declaration == "lowglobal" then
            v1 = ""
        elseif line.declaration == "highglobal" then
            v1 = "_G."
        end
        output = output..v1
        for index,var in pairs(line.names) do
            if index ~= 1 then
                output = output..","
            end
            highglobalvars[var] = line.declaration == "highglobal"
            output = output..var
        end
        output = output.."="
        for index,arg in pairs(line.values) do
            if index ~= 1 then
                output = output..","
            end
            output = output .. CompileExpression(arg)
        end
        output = output..";"
    elseif opcode == "ReturnStatement" then
        output = output.."return "
        for index,arg in pairs(line.values) do
            if index ~= 1 then
                output = output..","
            end
            output = output .. CompileExpression(arg)
        end
        output = output..";"
    elseif opcode == "AssignmentStatement" then
        for index, target in ipairs(line.targets) do
    local operator = line.operator or "="
    local value = CompileExpression(line.values[index])

    local lhs

    if target.type == "IndexExpression" then
        local object = CompileExpression(target.object)
        local key = CompileExpression(target.index)

        lhs = object .. "[" .. key .. "]"

    elseif target.type == "MemberExpression" then
        local object = CompileExpression(target.object)

        lhs = object .. "." .. target.property

    else
        local name = target.name
        lhs = highglobalvars[name] and "_G." .. name or name
    end

    if operator == "=" then
        output = output .. lhs .. "=" .. value .. ";"
    else
        local actualOperator = operator:sub(1, 1)

        output = output
            .. lhs .. "="
            .. lhs .. actualOperator
            .. "(" .. value .. ");"
    end
end
    elseif opcode == "CallStatement" then
        local callname = line.expression.callee.name or line.expression.callee.object.name 
        if callname == "import" then
            local id = tostring(math.random(100000, 999999))
            output = output.."function v" .. id .. "()" 
            local filepath = line.expression.arguments[1].value..".dd"
            if not luteapi_fs.exists(filepath) then
                filepath = (luteapi_process.args[1]:match("^(.*)[/\\]") or ".").."\\packages\\"..line.expression.arguments[1].value..".dd"
            end
            if filepath == "" then
                error("Faild to Find File: "..line.expression.arguments[1].value)
            end
            local file = luteapi_fs.open(filepath,"r")
            local importsource = luteapi_fs.read(file)
            luteapi_fs.close(file)
            for _, body in ipairs(Compiler.Parse(importsource)) do
                output = output .. ____workflow(body)
            end
            output = output .. "end " 
            if line.expression.arguments[2] then
                output = output .. line.expression.arguments[2].value .. "="
            end
            output = output .. "v"..id.."()"
            return output
        end
        output = output..callname..(line.expression.callee.property ~= nil and "."..line.expression.callee.property or "").."("
        for index,arg in pairs(line.expression.arguments) do
            if index ~= 1 then
                output = output..","
            end
            output = output .. CompileExpression(arg)
        end
        output = output..");"
    elseif opcode == "NumericForStatement" then
        local initial = CompileExpression(line.initial)
        local limit = CompileExpression(line.limit)
        local step = line.step and CompileExpression(line.step) or "1"

        output = output
            .. "for " .. line.name
            .. "=" .. initial
            .. "," .. limit
            .. "," .. step
            .. " do "

        for _, body in ipairs(line.body) do
            output = output .. ____workflow(body)
        end

        output = output .. " end;"
    elseif opcode == "LocalFunctionDeclaration" or opcode == "FunctionDeclaration" then
        local islocal = opcode == "LocalFunctionDeclaration" 
        output = output .. (islocal and "local " or "") .. "function " .. (line.name or CompileExpression(line.target)) .. "("
        for index,arg in pairs(line.value.parameters) do
            if index ~= 1 then
                output = output..","
            end
            output = output .. arg.name
        end
        output = output .. ")"
        for _, body in ipairs(line.value.body) do
            output = output .. ____workflow(body)
        end
        output = output .. " end;"
    elseif opcode == "GenericForStatement" then
        output = output
            .. "for " .. line.names[1]
            .. "," .. line.names[2]
            .. " in " .. CompileExpression(line.iterators[1])
            .. " do "

        for _, body in ipairs(line.body) do
            output = output .. ____workflow(body)
        end

        output = output .. " end;"
    elseif opcode == "WhileStatement" then
        output = output .. "while " .. CompileExpression(line.condition) .. " do "
        for _, body in ipairs(line.body) do
            output = output .. ____workflow(body)
        end
        output = output .. " end;"
    elseif opcode == "IfStatement" then
        for cul,branche in ipairs(line.branches) do
            output = output .. (cul ~= 1 and "else" or "") .. "if " .. CompileExpression(branche.condition).." then "
            for _, body in ipairs(branche.body) do
                output = output .. ____workflow(body)
            end
        end
        if line.elseBody then
            output = output .. " else " 
            for _, body in ipairs(line.elseBody) do
                output = output .. ____workflow(body)
            end
        end
        output = output .. " end;"
    elseif opcode == "BreakStatement" then
        output = output .. "break;"
    elseif opcode == "ContinueStatement" then
        output = output .. "continue;"
    end
    return output
end
if Config.Debug then
    print("Chaning Langs to Diamond to Luau...")
end
for _,line in pairs(ast) do
    codeoutput = codeoutput.. ____workflow(line)
end
if Config.Debug then
    print((Config.ExportToLua ~= nil and "Exporting File" or "Runing").." the Luau Exported Version...")
end
if Config.Debug then
    print("Printing the luau")
    print(codeoutput)
end
if Config.ExportToLua ~= nil then
    local file = luteapi_fs.open(Config.ExportToLua, "w")
    local addons = "luteapi_server = require('@lute/net/server')luteapi_io = require('@lute/io')luteapi_luau=require('@lute/luau')stdapi_json=require('@std/json')luteapi_process=require('@lute/process')luteapi_net=require('@lute/net/client')luteapi_fs=require('@lute/fs'); "
    if Config.Robloxluau then
        addons = ""
    end
    luteapi_fs.write(file,addons..codeoutput)
    luteapi_fs.close(file)
else
    local bytecode = luteapi_luau.compile(codeoutput)
    luteapi_luau.load(bytecode, "@Diamond")()
end
