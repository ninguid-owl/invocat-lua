#! /usr/local/bin/lua
-- a lexer, parser, and interpreter for invocat

-- the lexer and parser follow a producer/consumer pattern.
-- the lexer reads input (file or standard in) and returns tokens,
-- which are tables that have tag and value fields.
-- the parser requests tokens from the lexer and creates abstract syntax
-- nodes, which are formed into statements, which are ultimately evaluated.

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
  local comment = new_lex("COMMENT", '[-][-].*$')
  local punctuation = new_lex("PUNCT", '%p')
  local whitespace = new_lex("WHITE", '%s')

  return coroutine.create(function()
    local next_line = io.read
    if arg[1] then
      local f = assert(io.open(arg[1], "rb"))
      next_line = function () return f:read() end
    end
    local linenum = 0
    local line = next_line()
    while line do
      -- for each line
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
                    or comment(line, i)
                    or punctuation(line, i)
                    or whitespace(line, i)
        if match then
          send(match)
          i = i + match.length
        else i = i + 1
        end
      end
      line = next_line()
    end
  end)
end

-- parse tokens from the lexer
function parser(lexer)
  local prev_token = nil
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
    prev_token = token
    token = next_token
    next_token = receive(lexer) or new_token("EOF")
    return token
  end

  -- functions for the lowest level concrete syntax items
  -- white, ink
  -- white captures contiguous whitespace
  -- returns the whitespace, the token before the whitespace
  function make_white()
    local s = ""
    local p = prev_token
    while tag("WHITE") do
      s = s..token.value
      take()
    end
    if s == "" then return nil end
    return s, p
  end
  -- ink captures contiguous black: names and punctuation
  function make_ink()
    local s = ""
    while tag("NAME") or tag("PUNCT") do
      s = s..token.value
      take()
    end
    if s == "" then return nil end
    return s
  end
  -- name
  function make_name()
    local s = ""
    while tag("NAME") do
      s = s..token.value
      take()
    end
    if s == "" then return nil end
    return s
  end

  -- literal is ink [white literal]
  -- returns a Lit abstract syntax node or nil
  function make_literal(r)
    local l = make_ink()
    -- if we can't build up the literal, return what have so far
    if not l then return r end
    -- if we passed anything in recursively, then build on that
    l = r and r.value..l or l
    local w = make_white()
    if w and (tag("NAME") or tag("PUNCT") or tag("PARENL")) then
      l = lit(l..w)
      l = make_literal(l)
    else
      l = lit(l)
    end
    return l
  end
  -- reference is (name)
  -- returns a Ref abstract syntax node or nil
  function make_reference()
    local r = nil
    if tag("PARENL") and peek("NAME") then
      take() -- consume left paren
      r = make_name()
      if not tag("PARENR") then
        print("Error. Expecting ')' and found "..token.value)
        return nil
      end
      take() -- consume right paren
    end
    return r and ref(r) or nil
  end
  -- an item is a reference, literal, or mix of items
  -- returns Ref, Lit, or Mix abstract syntax node
  function make_Item()
    local i = nil
    -- ref or lit
    i = make_reference() or make_literal()
    if not i then
      --print("Error making item: could not find literal or reference")
      return nil
    end
    -- whitespace between items is sometimes significant
    local w, previous = make_white()
    -- if an item is followed by a newline or EOF, then that's it
    -- otherwise, it's followed by another item
    if tag("NEWLINE") or tag("EOF") then
      return i
    else
      local item = make_Item()
      if item then
        -- if we saw a ) before this item then keep the whitespace as a literal
        if previous and previous.tag == "PARENR" then
          local ws = lit(w)
          i = mix(i, ws)
        end
        return mix(i, item)
      else
        return i
      end
    end
  end
  -- itemlist
  function make_itemlist()
    local i = make_Item()
    if not i then
      --print("Error making itemlist: could not find item")
      return nil
    end
    local items = {i}
    while tag("PIPE") do
      -- match | and consume whitespace
      take()
      make_white()
      local item = make_Item()
      if not item then
        print("Error making itemlist: could not find item")
      else
        items[#items+1] = item
      end
    end
    return items
  end
  -- a List is a definition
  -- returns a Def abstract sytnax node or nil
  function make_List()
    if not peek("COLON") then
      return nil
    end
    local name = make_name()
    if not name then
      --print("Error making List: could not find NAME")
      return nil
    end
    -- match : and then consume whitespace
    take()
    make_white()
    local items = make_itemlist()
    return def(name, items)
  end

  -- parse the token stream and built a list of statements
  local statements = {}
  while token do
    -- a statement is a list definition or an item
    -- TODO or maybe just whitespace
    local s = make_List() or make_Item()
    if s then
      statements[#statements+1] = s
    else
      -- consume whatever it is
      -- print("Could not make a statement starting with *"..token.value.."*")
      take()
    end
    if tag("EOF") or peek("EOF") then break end
  end
  return statements
end

------------------------------------------------------------------- testing
-- create an abstract syntax node
function node(tag, value)
  node_tostring = function ()
    local s = "("..tag.." "
    if tag == "Ref" or tag == "Lit" then
      s = s..value
    elseif tag == "Mix" then
      for _,item in ipairs(value) do
        s = s.." "..item.tostring()
      end
    elseif tag == "Def" then
      -- value[1] is name, value[2] is items
      s = s..value[1].." "
      for _,item in ipairs(value[2]) do
        s = s.." "..item.tostring()
      end
    end
    return s..")"
  end
  return {tag=tag, value=value, tostring=node_tostring}
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
  -- ref. randomly pick an element of the list
  if tag == "Ref" then
    local name = v
    local list = state[name] or {} -- undefined names => {}
    if #list == 0 then return nothing end
    return eval(list[math.random(#list)])
  -- lit. eval to itself
  elseif tag == "Lit" then
    return v or nothing
  -- mix. eval to evaluation of the two items
  elseif tag == "Mix" then
    local t1 = eval(v[1]) -- or nothing
    local t2 = eval(v[2]) -- or nothing
    return t1..t2
  -- def. update state with the list
  elseif tag == "Def" then
    local name = v[1]
    local list = v[2]
    state[name] = list
  end
end

-- tests
--[[
-- abstract syntax nodes
local dog = lit('dog')
local cat = lit('cat')
local bear = lit('bear')
local owl = lit('owl')
local mouse = lit('mouse')
local deer = lit('deer')
local r = ref('animux')
local r2 = ref('recurse')
local l = lit("x")
local m = mix(l, r)
local mr = mix(l, mix(m, r))
local animux_list = {dog, cat, bear, owl, mouse, deer, r, m, mr}
local recurse_list = {mr, mr, l}
local animux = def('animux', animux_list)
local recurse = def('recurse', recurse_list)

eval(animux)
eval(recurse)
for i=1,50 do
  -- print(eval(r2))
end
--]]

--[[
print("tostring TEST SECTION------------------")
local test = def('wizard', {lit("rabbit")})
print(test.tostring())
print(recurse.tostring())
print(deer.tostring()) -- deer
print(r.tostring()) -- animux
print(mr.tostring()) -- x
print(animux.tostring())
print("END tostring TEST SECTION------------------")
--]]

function printstate()
  io.write('{')
  for k,v in pairs(state) do io.write(k,', ') end
  io.write('}\n')
end

local statements = parser(lexer())
printstate()
for _,s in ipairs(statements) do
  r = eval(s)
  if r then print('> ['..s.tag..'] '..r)
  else
    io.write('> [',s.tag,'] ')
    printstate()
  end
end
