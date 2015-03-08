#! /usr/local/bin/lua
-- a lexer ...

-- utility functions for working with coroutines
function receive(producer)
  local status, value = coroutine.resume(producer)
  return value
end

function send(x) coroutine.yield(x) end

-- read file
-- returns a coroutine that spits out tokens
function lexer()
  -- definition of a token
  -- has a tag, a value, a length
  function new_token(tag, value)
    local token = {}
    token.tag = tag
    token.value = value or ""
    token.length = token.value:len()
    return token
  end

  -- definition of a lexical item
  -- this function takes a tag and a pattern -- TODO and optional f
  -- returns a function that consumes a particular lexical item
  -- and produces a token / executes f
  function new_lex(tag, pattern)
    local f = function(content)
      --io.write("(", tag, " ", content, ")", "\n")
      return new_token(tag, content)
    end
    -- anchor pattern
    pattern = '^'..pattern
    -- return a function that matches the lexical item defined by pattern
    local function lex(line, index)
      index = index or 1
      local match = line:match(pattern, index)
      if match then return f(match) end
      return match
    end
    return lex
  end

  -- create the lexical items
  -- TODO literally in a table and then don't have to check them in the
  -- parse loop
  local name = new_lex("NAME", '[%a_]+') 
  local colon = new_lex("COLON", ':') 
  local pipe = new_lex("PIPE", '|') 
  local parenl = new_lex("PARENL", '[(]')
  local parenr = new_lex("PARENR", '[)]')
  local _literal = new_lex("_LITERAL", '"[^"]*"') -- TODO this is fake
  local comment = new_lex("COMMENT", '[-][-].*$')
  local punctuation = new_lex("PUNCT", '%p') -- TODO all punct! check late
  local whitespace = new_lex("WHITE", '%s')

  return coroutine.create(function()
    local f = assert(io.open(arg[1], "rb"))
    local linenum = 0
    while true do
      -- for each line
      local line = f:read(); if not line then break end -- TODO end token?
      linenum = linenum + 1
      -- if linenum > 1 then we've read a new line
      if linenum > 1 then send(new_token("NEWLINE", "")) end -- TODO
      io.write("\t\t", ("%5d "):format(linenum), line, "\n")

      -- start at index 1 and try to match patterns
      -- if no match, increment the index by 1
      local i = 1
      while i <= line:len() do
        local match = name(line, i)
                    or colon(line, i)
                    or pipe(line, i)
                    or parenl(line, i)
                    or parenr(line, i)
                    or _literal(line, i)
                    or comment(line, i)
                    or punctuation(line, i)
                    or whitespace(line, i)
        if match then
          send(match)
          i = i + match.length
        else i = i + 1
        end
      end
    end
  end)
end

-- parse tokens from the lexer
function parser(lexer)
  local token = receive(lexer)
  local next_token = receive(lexer)
  -- functions to look ahead at and consume tokens from the lexer
  function tag(tag)
    if token.tag == tag then return true end
    return false
  end
  function peek(tag)
    if next_token.tag == tag then return true end
    return false
  end
  function take()
    token = next_token
    next_token = receive(lexer) or new_token("EOF")
    return token
  end

  -- return a List
  function make_list()
    if tag("NAME") then
      local name = token.value
      take() -- :
      take()
      local item = make_item()
      local items = {item}
      while(tag("PIPE")) do
        take()
        local item = make_item()
        items[#items+1] = item
      end
      --take()
      return def(name, items)
    else
      print("Error parsing List. Expected a NAME but found " .. token.tag)
    end
  end

  function make_item()
    while(tag("WHITE")) do take() end
    local i = nil
    if tag("PARENL") and peek("NAME") then
      take() -- paren
      i = ref(token.value)
      take()
      if not tag("PARENR") then
        print("Error. Expecting ')' and found "..token.value)
      else
        take() -- paren
        while(tag("WHITE")) do take() end
      end
      if tag("NEWLINE") or tag("EOF") then return i
      else
        local item = make_item()
        if item then return mix(i, item) else return i end
        --return mix(i, make_item())
      end
    elseif tag("_LITERAL") then
      i = lit(token.value)
      take()
      while(tag("WHITE")) do take() end
      if tag("NEWLINE") or tag("EOF") then return i
      else
        local item = make_item()
        if item then return mix(i, item) else return i end
        --return mix(i, make_item())
      end
    end
    return i
  end

  local statements = {}
  while token do
    if tag("NAME") and peek("COLON") then
      statements[#statements+1] = make_list()
    elseif tag("_LITERAL") or tag("PARENL") then
      --take()
      local item = make_item()
      statements[#statements+1] = item
    else
      take()
    end
    if tag("EOF") or peek("EOF") then break end
    --io.write("(", token.tag, " ", token.value, ")", "\n")
  end
  return statements
end

------------------------------------------------------------------- testing
-- create an abstract syntax node
function node(tag, value)
  return {tag=tag, value=value}
end

-- abstract syntax
-- constructors
-- List
function def(name, items) return node("Def", {name, items}) end
-- Item
function ref(name) return node("Ref", name) end
function lit(literal) return node("Lit", literal) end
function mix(item1, item2) return node("Mix", {item1, item2}) end

state = {}
math.randomseed(os.time())
function eval(term)
  local tag = term.tag
  local v = term.value
  local nothing = ""
  -- if not v then return nil end -- TODO nec?
  -- ref. randomly pick an element of the list
  if tag == "Ref" then
    local name = v
    local list = state[name] or {} -- undefined names => {}
    if #list == 0 then return nothing end -- TODO test
    return eval(list[math.random(#list)])
  -- lit. eval to itself
  elseif tag == "Lit" then
    return v or nothing
  -- mix. eval to evaluation of the two items
  elseif tag == "Mix" then
    local t1 = eval(v[1]) or nothing
    local t2 = eval(v[2]) or nothing
    return t1..t2
  elseif tag == "Def" then
    local name = v[1]
    local list = v[2]
    state[name] = list
    -- return ???
  end
end

-- tests
local hihi = lit("hihihi hohoh")
local a = {lit('dog'), lit('bear'), lit('cat')}
local animux = def('animux', a)
local r = ref('animux')
local mux = mix(mix(r, r), hihi)

eval(animux)
print(eval(r))
print(eval(mux))


local statements = parser(lexer())
for _,s in ipairs(statements) do
  print(eval(s))
end

-- use coroutines to set up a producer/consumer model for the lexer and the
-- parser
-- the lexer reads input and returns tokens, which 
-- are tables that have tag and value fields (and others?)
-- the parser requests tokens from the lexer and builds an AST
-- TODO how is the AST represented here?
-- i think once the lexer returns an end of program token then the parser
-- finalizes the AST
-- finally, we evaluate the AST
