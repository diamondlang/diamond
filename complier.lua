--[=[
    Custom Language Compiler / Parser
    ---------------------------------
    Converts source text into an Abstract Syntax Tree (AST).

    Supported syntax:
      * local, lowglobal and highglobal declarations
      * numbers, strings, triple-quoted multiline strings
      * true/false, True/False, nil/null
      * arithmetic, comparison, logical, concatenation and unary operators
      * tables: array fields, name fields and [expression] fields
      * indexing, member access and function calls
      * anonymous functions, named functions and varargs (...)
      * assignments, multiple assignments and compound assignments
      * brace blocks: if / elseif / else, while, repeat / until, for, functions
      * return, break and continue
      * semicolons are optional statement separators, equivalent to newlines
      * -- line comments and --[[ block comments ]]

    This module only parses source. It DOES NOT execute the source code.

    Usage:
        local Compiler = require("compiler")
        local ast = Compiler.Parse(source)

    AST nodes are ordinary Lua tables. Every node has a `type`, `line` and
    `column` field, plus fields specific to that node type.
]=]

local Compiler = {
    VERSION = "2.1.0"
}

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------

local function makeNode(kind, fields, token)
    fields = fields or {}
    fields.type = kind

    if token then
        fields.line = token.line
        fields.column = token.column
    end

    return fields
end

local function locationError(kind, message, line, column)
    error(string.format("%s error at %d:%d: %s", kind, line, column, message), 0)
end

local function isIdentifierStart(char)
    return char ~= "" and char:match("^[%a_]$") ~= nil
end

local function isIdentifierPart(char)
    return char ~= "" and char:match("^[%w_]$") ~= nil
end

------------------------------------------------------------------------
-- Lexer
------------------------------------------------------------------------

local KEYWORDS = {
    local_ = true,
    lowglobal_ = true,
    highglobal_ = true,
    function_ = true,
    if_ = true,
    elseif_ = true,
    else_ = true,
    while_ = true,
    for_ = true,
    in_ = true,
    repeat_ = true,
    until_ = true,
    return_ = true,
    break_ = true,
    continue_ = true,
    and_ = true,
    or_ = true,
    not_ = true,
    true_ = true,
    false_ = true,
    True_ = true,
    False_ = true,
    nil_ = true,
    null_ = true
}

-- Long-bracket strings/comments use Lua's [=[ ... ]=] form.
local function getLongBracketOpen(source, position)
    local equals = source:sub(position):match("^%[(=*)%[")
    if equals == nil then
        return nil
    end

    return #equals, position + #equals + 2
end

function Compiler.Tokenize(source)
    assert(type(source) == "string", "Compiler.Tokenize expects a string")

    local tokens = {}
    local i = 1
    local line = 1
    local column = 1
    local length = #source

    local function current()
        return source:sub(i, i)
    end

    local function addToken(tokenType, value, raw, tokenLine, tokenColumn)
        tokens[#tokens + 1] = {
            type = tokenType,
            value = value,
            raw = raw,
            line = tokenLine or line,
            column = tokenColumn or column
        }
    end

    local function advanceOne()
        local char = current()
        if char == "\n" then
            i = i + 1
            line = line + 1
            column = 1
        else
            i = i + 1
            column = column + 1
        end
        return char
    end

    local function advanceText(text)
        for _ = 1, #text do
            advanceOne()
        end
    end

    local function lexError(message, atLine, atColumn)
        locationError("Lex", message, atLine or line, atColumn or column)
    end

    local function readNumber()
        local start = i
        local startLine, startColumn = line, column

        if source:sub(i, i + 1):lower() == "0x" then
            advanceText(source:sub(i, i + 1))
            local digitsStart = i

            while current():match("^[%da-fA-F]$") do
                advanceOne()
            end

            if i == digitsStart then
                lexError("invalid hexadecimal number", startLine, startColumn)
            end
        else
            if current() == "." then
                advanceOne()
                while current():match("^%d$") do
                    advanceOne()
                end
            else
                while current():match("^%d$") do
                    advanceOne()
                end

                -- Do not consume the first dot of a concatenation operator.
                if current() == "." and source:sub(i + 1, i + 1) ~= "." then
                    advanceOne()
                    while current():match("^%d$") do
                        advanceOne()
                    end
                end
            end

            if current() == "e" or current() == "E" then
                advanceOne()
                if current() == "+" or current() == "-" then
                    advanceOne()
                end

                local exponentStart = i
                while current():match("^%d$") do
                    advanceOne()
                end

                if i == exponentStart then
                    lexError("invalid exponent", startLine, startColumn)
                end
            end
        end

        local raw = source:sub(start, i - 1)
        local value = tonumber(raw)

        if value == nil then
            lexError("invalid number " .. raw, startLine, startColumn)
        end

        addToken("Number", value, raw, startLine, startColumn)
    end

    local function readQuotedString(quote)
        local start = i
        local startLine, startColumn = line, column
        local triple = quote == '"' and source:sub(i, i + 2) == '"""'
        local delimiter = triple and '"""' or quote
        local value = {}

        advanceText(delimiter)

        if triple then
            local closeAt = source:find(delimiter, i, true)
            if not closeAt then
                lexError("unfinished triple-quoted string", startLine, startColumn)
            end

            local content = source:sub(i, closeAt - 1)
            value[1] = content
            advanceText(content)
            advanceText(delimiter)
        else
            local terminated = false

            while i <= length do
                local char = current()

                if char == quote then
                    advanceOne()
                    terminated = true
                    break
                elseif char == "\n" then
                    lexError("newline inside quoted string; use triple quotes", startLine, startColumn)
                elseif char == "\\" then
                    advanceOne()
                    if i > length then
                        lexError("unfinished escape sequence", startLine, startColumn)
                    end

                    local escaped = current()
                    local escapes = {
                        n = "\n",
                        r = "\r",
                        t = "\t",
                        b = "\b",
                        f = "\f",
                        ["\\"] = "\\",
                        ['"'] = '"',
                        ["'"] = "'",
                        ["0"] = "\0"
                    }

                    if escaped == "x" then
                        local hex = source:sub(i + 1, i + 2)
                        if not hex:match("^%x%x$") then
                            lexError("expected two hexadecimal digits after \\x", line, column)
                        end
                        value[#value + 1] = string.char(tonumber(hex, 16))
                        advanceText("x" .. hex)
                    else
                        value[#value + 1] = escapes[escaped] or escaped
                        advanceOne()
                    end
                else
                    value[#value + 1] = char
                    advanceOne()
                end
            end

            if not terminated then
                lexError("unfinished string", startLine, startColumn)
            end
        end

        local raw = source:sub(start, i - 1)
        addToken("String", table.concat(value), raw, startLine, startColumn)
    end

    local function skipLongComment()
        local startLine, startColumn = line, column
        local equals, contentStart = getLongBracketOpen(source, i + 2)

        if equals == nil then
            while i <= length and current() ~= "\n" do
                advanceOne()
            end
            return
        end

        local close = "]" .. string.rep("=", equals) .. "]"
        local closeAt = source:find(close, contentStart, true)

        if not closeAt then
            lexError("unfinished long comment", startLine, startColumn)
        end

        advanceText(source:sub(i, closeAt + #close - 1))
    end

    local operators = {
        "...", "..=", "//=", "==", "!=", "~=", ">=", "<=",
        "+=", "-=", "*=", "/=", "%=", "^=", "//", "..",
        "<<", ">>", "::", "->"
    }

    while i <= length do
        local char = current()

        if char == " " or char == "\t" or char == "\r" or char == "\f" then
            advanceOne()

        elseif char == "\n" then
            local tokenLine, tokenColumn = line, column
            advanceOne()
            addToken("Newline", "\n", "\n", tokenLine, tokenColumn)

        elseif char == ";" then
            local tokenLine, tokenColumn = line, column
            advanceOne()
            addToken("Newline", "\n", ";", tokenLine, tokenColumn)

        elseif source:sub(i, i + 1) == "--" then
            skipLongComment()

        elseif char == '"' or char == "'" then
            readQuotedString(char)

        elseif char == "[" and getLongBracketOpen(source, i) ~= nil then
            local startLine, startColumn = line, column
            local equals, contentStart = getLongBracketOpen(source, i)
            local close = "]" .. string.rep("=", equals) .. "]"
            local closeAt = source:find(close, contentStart, true)

            if not closeAt then
                lexError("unfinished long-bracket string", startLine, startColumn)
            end

            local content = source:sub(contentStart, closeAt - 1)
            local rawEnd = closeAt + #close - 1
            local raw = source:sub(i, rawEnd)
            advanceText(raw)
            addToken("String", content, raw, startLine, startColumn)

        elseif char:match("^%d$") or
               (char == "." and source:sub(i + 1, i + 1):match("^%d$")) then
            readNumber()

        elseif isIdentifierStart(char) then
            local start = i
            local startLine, startColumn = line, column

            advanceOne()
            while isIdentifierPart(current()) do
                advanceOne()
            end

            local value = source:sub(start, i - 1)
            local keywordKey = value .. "_"
            local tokenType = KEYWORDS[keywordKey] and "Keyword" or "Identifier"
            addToken(tokenType, value, value, startLine, startColumn)

        else
            local matched

            for _, operator in ipairs(operators) do
                if source:sub(i, i + #operator - 1) == operator then
                    matched = operator
                    break
                end
            end

            if matched then
                local tokenLine, tokenColumn = line, column
                advanceText(matched)
                addToken("Operator", matched, matched, tokenLine, tokenColumn)

            elseif char:match("^[%+%-%*/%%%^%=<>%(%)%{%}%[%],%.;:#&|~]$") then
                local tokenLine, tokenColumn = line, column
                advanceOne()
                addToken("Symbol", char, char, tokenLine, tokenColumn)

            else
                lexError("unexpected character " .. string.format("%q", char))
            end
        end
    end

    tokens[#tokens + 1] = {
        type = "EOF",
        value = "<eof>",
        raw = "",
        line = line,
        column = column
    }

    return tokens
end

------------------------------------------------------------------------
-- Parser
------------------------------------------------------------------------

function Compiler.Parse(source)
    local tokens = Compiler.Tokenize(source)
    local position = 1

    local function peek(offset)
        return tokens[position + (offset or 0)] or tokens[#tokens]
    end

    local function advance()
        local token = peek()
        if token.type ~= "EOF" then
            position = position + 1
        end
        return token
    end

    local function at(value)
        return peek().value == value
    end

    local function match(value)
        if at(value) then
            return advance()
        end
        return nil
    end

    local function fail(message, token)
        token = token or peek()
        locationError("Parse", message, token.line, token.column)
    end

    local function expect(value)
        if not at(value) then
            fail("expected " .. string.format("%q", value) ..", got " .. string.format("%q", peek().value))
        end
        return advance()
    end

    local function expectIdentifier()
        local token = peek()
        if token.type ~= "Identifier" then
            fail("expected identifier, got " .. string.format("%q", token.value), token)
        end
        return advance()
    end

    local function skipNewlines()
        while peek().type == "Newline" do
            advance()
        end
    end

    -- Newlines and semicolons both separate statements. Neither is required
    -- at the end of a line or before a closing brace.
    local function skipSeparators()
        while peek().type == "Newline" or at(";") do
            advance()
        end
    end

    local function isBlockEnd(stops)
        return peek().type == "EOF" or stops[peek().value] == true
    end

    local parseExpression
    local parseStatement
    local parseBlock

    --------------------------------------------------------------------
    -- Expressions
    --------------------------------------------------------------------

    local PRECEDENCE = {
        ["or"] = 1,
        ["and"] = 2,
        ["=="] = 3, ["!="] = 3, ["~="] = 3,
        ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3,
        ["|"] = 4,
        ["~"] = 5,
        ["&"] = 6,
        ["<<"] = 7, [">>"] = 7,
        [".."] = 8,
        ["+"] = 9, ["-"] = 9,
        ["*"] = 10, ["/"] = 10, ["//"] = 10, ["%"] = 10,
        ["^"] = 12
    }

    local RIGHT_ASSOCIATIVE = {
        ["^"] = true,
        [".."] = true
    }

    local function parseExpressionList()
        local expressions = { parseExpression(1) }

        while true do
            skipNewlines()
            if not match(",") then
                break
            end
            skipNewlines()
            expressions[#expressions + 1] = parseExpression(1)
        end

        return expressions
    end

    local function parseFunctionBody(functionToken, implicitSelf)
        skipNewlines()
        expect("(")
        skipNewlines()

        local parameters = {}
        local isVararg = false

        if not at(")") then
            while true do
                if at("...") then
                    local varargToken = advance()
                    parameters[#parameters + 1] = makeNode("VarargParameter", {}, varargToken)
                    isVararg = true
                    break
                end

                local parameter = expectIdentifier()
                parameters[#parameters + 1] = makeNode("Parameter", {
                    name = parameter.value
                }, parameter)

                skipNewlines()
                if not match(",") then
                    break
                end
                skipNewlines()
            end
        end

        skipNewlines()
        expect(")")
        skipNewlines()

        if implicitSelf then
            table.insert(parameters, 1, makeNode("Parameter", {
                name = "self",
                implicit = true
            }, functionToken))
        end

        expect("{")
        local body = parseBlock({ ["}"] = true })
        expect("}")

        return makeNode("FunctionExpression", {
            parameters = parameters,
            vararg = isVararg,
            body = body
        }, functionToken)
    end

    local function parseTableConstructor(openToken)
        local fields = {}
        skipSeparators()

        while not at("}") do
            if peek().type == "EOF" then
                fail("unfinished table constructor", openToken)
            end

            local field

            if match("[") then
                local key = parseExpression(1)
                skipNewlines()
                expect("]")
                skipNewlines()
                expect("=")
                skipNewlines()

                field = makeNode("TableIndexField", {
                    key = key,
                    value = parseExpression(1)
                }, openToken)

            elseif peek().type == "Identifier" and peek(1).value == "=" then
                local key = advance()
                advance() -- equals
                skipNewlines()

                field = makeNode("TableNameField", {
                    name = key.value,
                    value = parseExpression(1)
                }, key)

            else
                field = makeNode("TableArrayField", {
                    value = parseExpression(1)
                }, peek(-1))
            end

            fields[#fields + 1] = field
            skipNewlines()

            if match(",") or match(";") then
                skipSeparators()
            elseif not at("}") and peek().type ~= "Newline" then
                -- Adjacent fields without a comma are rejected when they cannot
                -- form a valid continuation of the previous expression.
                if at("EOF") then
                    fail("unfinished table constructor", openToken)
                end
            else
                skipSeparators()
            end
        end

        expect("}")

        return makeNode("TableConstructor", {
            fields = fields
        }, openToken)
    end

    local function parsePrimary()
        local token = advance()
        local value = token.value

        if token.type == "Number" then
            return makeNode("NumberLiteral", {
                value = value,
                raw = token.raw
            }, token)

        elseif token.type == "String" then
            return makeNode("StringLiteral", {
                value = value,
                raw = token.raw
            }, token)

        elseif value == "true" or value == "True" then
            return makeNode("BooleanLiteral", { value = true }, token)

        elseif value == "false" or value == "False" then
            return makeNode("BooleanLiteral", { value = false }, token)

        elseif value == "nil" then
            return makeNode("NilLiteral", {}, token)

        elseif value == "null" then
            return makeNode("NullLiteral", {}, token)

        elseif value == "..." then
            return makeNode("VarargExpression", {}, token)

        elseif value == "(" then
            skipNewlines()
            local expression = parseExpression(1)
            skipNewlines()
            expect(")")
            return makeNode("ParenthesizedExpression", {
                expression = expression
            }, token)

        elseif value == "{" then
            return parseTableConstructor(token)

        elseif value == "function" then
            return parseFunctionBody(token, false)

        elseif token.type == "Identifier" then
            return makeNode("Identifier", {
                name = value
            }, token)
        end

        fail("unexpected token in expression: " .. string.format("%q", value), token)
    end

    local function parseArguments(openToken)
        local arguments = {}
        skipNewlines()

        if not at(")") then
            arguments = parseExpressionList()
            skipNewlines()
        end

        expect(")")

        return arguments
    end

    local function parsePostfix()
        local expression = parsePrimary()

        while true do
            if match(".") then
                local property = expectIdentifier()
                expression = makeNode("MemberExpression", {
                    object = expression,
                    property = property.value
                }, property)

            elseif match("[") then
                local openToken = tokens[position - 1]
                skipNewlines()
                local index = parseExpression(1)
                skipNewlines()
                expect("]")

                expression = makeNode("IndexExpression", {
                    object = expression,
                    index = index
                }, openToken)

            elseif match(":") then
                local method = expectIdentifier()
                skipNewlines()
                local openToken = expect("(")
                local arguments = parseArguments(openToken)

                expression = makeNode("MethodCallExpression", {
                    receiver = expression,
                    method = method.value,
                    arguments = arguments
                }, method)

            elseif match("(") then
                local openToken = tokens[position - 1]
                local arguments = parseArguments(openToken)

                expression = makeNode("CallExpression", {
                    callee = expression,
                    arguments = arguments
                }, openToken)

            else
                break
            end
        end

        return expression
    end

    local function parseUnary()
        local token = peek()
        local operator = token.value

        if operator == "not" or operator == "#" or operator == "-" or
           operator == "+" or operator == "~" then
            advance()
            skipNewlines()
            local unaryPrecedence = operator == "not" and 3 or 11
            return makeNode("UnaryExpression", {
                operator = operator,
                operand = parseExpression(unaryPrecedence)
            }, token)
        end

        return parsePostfix()
    end

    parseExpression = function(minimumPrecedence)
        minimumPrecedence = minimumPrecedence or 1
        local left = parseUnary()

        while true do
            local operatorToken = peek()
            local operator = operatorToken.value
            local precedence = PRECEDENCE[operator]

            if not precedence or precedence < minimumPrecedence then
                break
            end

            advance()
            skipNewlines()

            local nextMinimum = precedence
            if not RIGHT_ASSOCIATIVE[operator] then
                nextMinimum = precedence + 1
            end

            local right = parseExpression(nextMinimum)

            left = makeNode("BinaryExpression", {
                operator = operator,
                left = left,
                right = right
            }, operatorToken)
        end

        return left
    end

    --------------------------------------------------------------------
    -- Statements and blocks
    --------------------------------------------------------------------

    parseBlock = function(stops)
        local statements = {}
        skipSeparators()

        while not isBlockEnd(stops) do
            local oldPosition = position
            statements[#statements + 1] = parseStatement()

            if position == oldPosition then
                fail("parser made no progress")
            end

            skipSeparators()
        end

        return statements
    end

    local function parseDeclaration(declarationToken)
        if at("function") then
            local functionToken = advance()
            local name = expectIdentifier()
            local fn = parseFunctionBody(functionToken, false)

            return makeNode("LocalFunctionDeclaration", {
                name = name.value,
                value = fn
            }, declarationToken)
        end

        local names = {}
        names[#names + 1] = expectIdentifier().value

        while true do
            skipNewlines()
            if not match(",") then
                break
            end
            skipNewlines()
            names[#names + 1] = expectIdentifier().value
        end

        local values = {}
        if match("=") then
            skipNewlines()
            values = parseExpressionList()
        end

        return makeNode("VariableDeclaration", {
            declaration = declarationToken.value,
            names = names,
            values = values
        }, declarationToken)
    end

    local function parseFunctionName()
        local name = expectIdentifier()
        local target = makeNode("Identifier", { name = name.value }, name)
        local method = false

        while at(".") or at(":") do
            local separator = advance()
            local property = expectIdentifier()
            target = makeNode("MemberExpression", {
                object = target,
                property = property.value
            }, property)

            if separator.value == ":" then
                method = true
                break
            end
        end

        return target, method
    end

    local function parseIf(ifToken)
        local branches = {}
        local condition = parseExpression(1)
        skipNewlines()
        expect("{")

        branches[#branches + 1] = {
            condition = condition,
            body = parseBlock({ ["}"] = true })
        }
        expect("}")

        skipSeparators()
        while match("elseif") do
            local branchCondition = parseExpression(1)
            skipNewlines()
            expect("{")

            branches[#branches + 1] = {
                condition = branchCondition,
                body = parseBlock({ ["}"] = true })
            }
            expect("}")
            skipSeparators()
        end

        local elseBody
        if match("else") then
            skipNewlines()
            expect("{")
            elseBody = parseBlock({ ["}"] = true })
            expect("}")
        end

        return makeNode("IfStatement", {
            branches = branches,
            elseBody = elseBody
        }, ifToken)
    end

    local function parseWhile(whileToken)
        local condition = parseExpression(1)
        skipNewlines()
        expect("{")
        local body = parseBlock({ ["}"] = true })
        expect("}")

        return makeNode("WhileStatement", {
            condition = condition,
            body = body
        }, whileToken)
    end

    local function parseRepeat(repeatToken)
        skipNewlines()
        expect("{")
        local body = parseBlock({ ["}"] = true })
        expect("}")
        skipSeparators()
        expect("until")
        skipNewlines()
        local condition = parseExpression(1)

        return makeNode("RepeatUntilStatement", {
            body = body,
            condition = condition
        }, repeatToken)
    end

    local function parseFor(forToken)
        local names = { expectIdentifier().value }

        while true do
            skipNewlines()
            if not match(",") then
                break
            end
            skipNewlines()
            names[#names + 1] = expectIdentifier().value
        end

        if match("=") then
            skipNewlines()
            local initial = parseExpression(1)
            skipNewlines()
            expect(",")
            skipNewlines()
            local limit = parseExpression(1)
            local step

            skipNewlines()
            if match(",") then
                skipNewlines()
                step = parseExpression(1)
            end

            skipNewlines()
            expect("{")
            local body = parseBlock({ ["}"] = true })
            expect("}")

            if #names ~= 1 then
                fail("numeric for loop expects exactly one variable", forToken)
            end

            return makeNode("NumericForStatement", {
                name = names[1],
                initial = initial,
                limit = limit,
                step = step,
                body = body
            }, forToken)
        end

        expect("in")
        skipNewlines()
        local iterators = parseExpressionList()
        skipNewlines()
        expect("{")
        local body = parseBlock({ ["}"] = true })
        expect("}")

        return makeNode("GenericForStatement", {
            names = names,
            iterators = iterators,
            body = body
        }, forToken)
    end

    local function parseReturn(returnToken)
        local values = {}
        local nextToken = peek()
        local terminators = {
            ["elseif"] = true,
            ["else"] = true,
            ["until"] = true,
            ["}"] = true
        }

        if nextToken.type ~= "EOF" and nextToken.type ~= "Newline" and
           not terminators[nextToken.value] then
            values = parseExpressionList()
        end

        return makeNode("ReturnStatement", {
            values = values
        }, returnToken)
    end

    local function isAssignable(expression)
        return expression.type == "Identifier" or
               expression.type == "MemberExpression" or
               expression.type == "IndexExpression"
    end

    local function isCall(expression)
        return expression.type == "CallExpression" or
               expression.type == "MethodCallExpression"
    end

    parseStatement = function()
        local token = peek()
        local value = token.value

        if match("local") or match("lowglobal") or match("highglobal") then
            return parseDeclaration(tokens[position - 1])

        elseif match("function") then
            local functionToken = tokens[position - 1]
            local target, isMethod = parseFunctionName()
            local fn = parseFunctionBody(functionToken, isMethod)

            return makeNode("FunctionDeclaration", {
                target = target,
                value = fn,
                method = isMethod
            }, functionToken)

        elseif match("if") then
            return parseIf(token)

        elseif match("while") then
            return parseWhile(token)

        elseif match("repeat") then
            return parseRepeat(token)

        elseif match("for") then
            return parseFor(token)

        elseif match("{") then
            local body = parseBlock({ ["}"] = true })
            expect("}")
            return makeNode("DoStatement", { body = body }, token)

        elseif match("return") then
            return parseReturn(token)

        elseif match("break") then
            return makeNode("BreakStatement", {}, token)

        elseif match("continue") then
            return makeNode("ContinueStatement", {}, token)
        end

        -- An expression at statement level is either an assignment target or
        -- a function/method call. Comma-separated expressions support
        -- multiple assignment: a, b = 1, 2.
        local targets = parseExpressionList()
        local operator = peek().value

        if operator == "=" or operator == "+=" or operator == "-=" or
           operator == "*=" or operator == "/=" or operator == "%=" or
           operator == "^=" or operator == "..=" or operator == "//=" then
            local operatorToken = advance()

            if operator ~= "=" and #targets ~= 1 then
                fail("compound assignment only supports one target", operatorToken)
            end

            for _, target in ipairs(targets) do
                if not isAssignable(target) then
                    fail("invalid assignment target", operatorToken)
                end
            end

            skipNewlines()
            local values = parseExpressionList()

            return makeNode("AssignmentStatement", {
                targets = targets,
                operator = operator,
                values = values
            }, operatorToken)
        end

        if #targets ~= 1 or not isCall(targets[1]) then
            fail("expected assignment or function call", token)
        end

        return makeNode("CallStatement", {
            expression = targets[1]
        }, token)
    end

    local ast = parseBlock({})

    if peek().type ~= "EOF" then
        fail("unexpected token after program")
    end

    return ast
end

------------------------------------------------------------------------
-- Convenience API
------------------------------------------------------------------------

function Compiler.ParseWithTokens(source)
    local tokens = Compiler.Tokenize(source)
    local ast = Compiler.Parse(source)
    return ast, tokens
end

-- Non-throwing API: returns ast, nil on success or nil, errorMessage on failure.
function Compiler.TryParse(source)
    local ok, result = pcall(Compiler.Parse, source)
    if ok then
        return result, nil
    end
    return nil, tostring(result)
end

return Compiler
