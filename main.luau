local Compiler = require("./complier")
luteapi_luau = require("@lute/luau")
luteapi_process = require("@lute/process")
luteapi_net = require("@lute/net/client")
luteapi_fs = require("@lute/fs")
stdapi_json = require("@std/json")
luteapi_io = require("@lute/io")
local argsofapp = {...}

local Config = {
    Debug = false,
    ExportToLua = nil,
    Input = argsofapp[2]
}

local i = 3

while i <= #argsofapp do
    local value = argsofapp[i]

    if value == "--debug" then
        Config.Debug = true

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
    print("diamond <diamond file path> --debug > debuging the code workflow")
    print("diamond <diamond file path> --exporttoluau > export to luau code without runing")
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
            .. op ..
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
local codeoutput = "pi=math.pi;function thread(...)return spawn(...)end function tfind(...)return table.find(...)end function append(...)table.append(...)end function insert(...)table.insert(...)end function pn(...)print(...)end function wn(...)warn(...)end function fo(...)info(...)end function er(...)error(...)end function len(item)return #item end function rad(deg)return math.rad(deg)end function deg(rad)return math.deg(rad)end function cos(deg)return math.cos(math.rad(deg))end function sin(deg)return math.sin(math.rad(deg))end function readfile(filepath)local file=luteapi_fs.open(filepath,'r')local code=luteapi_fs.read(file)luteapi_fs.close(file)return code end function writefile(filepath,code)local file=luteapi_fs.open(filepath,'w')luteapi_fs.write(file,code)luteapi_fs.close(file)end function request(...)return luteapi_net.request(...)end function runcmd(...)return luteapi_process.system(...)end function json_decode(...)return stdapi_json.deserialize(...)end function json_encode(tab)return stdapi_json.serialize(tab, true)end function tostr(...)return tostring(...)end function tonum(...)return tonumber(...)end function floor(...)return math.floor(...)end function round(...)return math.round(...)end function clamp(...)return math.clamp(...)end function runtest(...)return pcall(...)end function addpn(...)luteapi_io.write(...)end function input(str)luteapi_io.write(str or '')return luteapi_io.read()end function runluau(...)return luteapi_luau.load(luteapi_luau.compile(...),'@Luau')() end\n"
local function workflow(line) 
    local opcode = line.type
    if opcode == "VariableDeclaration" then
        local v1 = "local "
        if line.declaration == "lowglobal" then
            v1 = ""
        elseif line.declaration == "highglobal" then
            v1 = "_G."
        end
        codeoutput = codeoutput..v1
        for index,var in pairs(line.names) do
            if index ~= 1 then
                codeoutput = codeoutput..","
            end
            highglobalvars[var] = line.declaration == "highglobal"
            codeoutput = codeoutput..var
        end
        codeoutput = codeoutput.."="
        for index,arg in pairs(line.values) do
            if index ~= 1 then
                codeoutput = codeoutput..","
            end
            codeoutput = codeoutput .. CompileExpression(arg)
        end
        codeoutput = codeoutput..";"
    elseif opcode == "ReturnStatement" then
        codeoutput = codeoutput.."return "
        for index,arg in pairs(line.values) do
            if index ~= 1 then
                codeoutput = codeoutput..","
            end
            codeoutput = codeoutput .. CompileExpression(arg)
        end
        codeoutput = codeoutput..";"
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
        codeoutput = codeoutput .. lhs .. "=" .. value .. ";"
    else
        local actualOperator = operator:sub(1, 1)

        codeoutput = codeoutput
            .. lhs .. "="
            .. lhs .. actualOperator
            .. "(" .. value .. ");"
    end
end
    elseif opcode == "CallStatement" then
        local callname = line.expression.callee.name or line.expression.callee.object.name 
        codeoutput = codeoutput..callname..(line.expression.callee.property ~= nil and "."..line.expression.callee.property or "").."("
        for index,arg in pairs(line.expression.arguments) do
            if index ~= 1 then
                codeoutput = codeoutput..","
            end
            codeoutput = codeoutput .. CompileExpression(arg)
        end
        codeoutput = codeoutput..");"
    elseif opcode == "NumericForStatement" then
        local initial = CompileExpression(line.initial)
        local limit = CompileExpression(line.limit)
        local step = line.step and CompileExpression(line.step) or "1"

        codeoutput = codeoutput
            .. "for " .. line.name
            .. "=" .. initial
            .. "," .. limit
            .. "," .. step
            .. " do "

        for _, body in ipairs(line.body) do
            workflow(body)
        end

        codeoutput = codeoutput .. " end;"
    elseif opcode == "LocalFunctionDeclaration" or opcode == "FunctionDeclaration" then
        local islocal = opcode == "LocalFunctionDeclaration" 
        codeoutput = codeoutput .. (islocal and "local " or "") .. "function " .. (line.name or CompileExpression(line.target)) .. "("
        for index,arg in pairs(line.value.parameters) do
            if index ~= 1 then
                codeoutput = codeoutput..","
            end
            codeoutput = codeoutput .. arg.name
        end
        codeoutput = codeoutput .. ")"
        for _, body in ipairs(line.value.body) do
            workflow(body)
        end
        codeoutput = codeoutput .. " end;"
    elseif opcode == "WhileStatement" then
        codeoutput = codeoutput .. "while " .. CompileExpression(line.condition) .. " do "
        for _, body in ipairs(line.body) do
            workflow(body)
        end
        codeoutput = codeoutput .. " end;"
    elseif opcode == "IfStatement" then
        for cul,branche in ipairs(line.branches) do
            codeoutput = codeoutput .. (cul ~= 1 and "else" or "") .. "if " .. CompileExpression(branche.condition).." then "
            for _, body in ipairs(branche.body) do
                workflow(body)
            end
        end
        if line.elseBody then
            codeoutput = codeoutput .. " else " 
            for _, body in ipairs(line.elseBody) do
                workflow(body)
            end
        end
        codeoutput = codeoutput .. " end;"
    elseif opcode == "BreakStatement" then
        codeoutput = codeoutput .. "break;"
    elseif opcode == "ContinueStatement" then
        codeoutput = codeoutput .. "continue;"
    end
end
if Config.Debug then
    print("Chaning Langs to Diamond to Luau...")
end
for _,line in pairs(ast) do
    workflow(line)
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
    luteapi_fs.write(file,"luteapi_io = require('@lute/io')luteapi_luau=require('@lute/luau')stdapi_json=require('@std/json')luteapi_process=require('@lute/process')luteapi_net=require('@lute/net/client')luteapi_fs=require('@lute/fs'); "..codeoutput)
    luteapi_fs.close(file)
else
    local bytecode = luteapi_luau.compile(codeoutput)
    luteapi_luau.load(bytecode, "@Diamond")()
end