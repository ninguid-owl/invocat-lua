#!/usr/bin/env lua

-- Invocat: a nondeterministic, generative programming language
-- by Christopher and Matthew Antoun
-- at the University of California, Santa Cruz
-- Copyright 2015

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
  local mt = {}
  mt.__tostring = function(t)
    return ("(%s %s)"):format(t.tag, t.value)
  end
  function new_token(tag, value)
    local token = {}
    setmetatable(token, mt)
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
      -- TODO: rm
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
  local lex_items = {
    new_lex("1RULE", '[-][-][-]+.*$'),
    new_lex("2RULE", '[=][=][=]+.*$'),
    new_lex("COMMENT", '[-][-]%s+.*$'),
    -- allow certain punctuation in names
    new_lex("NUMBER", '[%d]+'),
    new_lex("NAME", '[%w_%!\'?.,;]+'),
    -- TODO don't nec need to separate out punctuation
    new_lex("LPAREN", '[(]'),
    new_lex("RPAREN", '[)]'),
    new_lex("COLON", '%s?:'), -- TODO %s* ?
    new_lex("LARROW", '%s?<[-]'), -- TODO %s* ?
    new_lex("PIPE", '|'), -- TODO surround with white ?
    new_lex("ESCAPE", '\\[n()]'),
    new_lex("BREAK", '\\$'),
    new_lex("PUNCT", '%p'),
    new_lex("WHITE", '%s'),
  }

  return coroutine.create(function()
    local next_line = io.read
    if arg[1] then
      local f, status = io.open(arg[1], "rb")
      if status then
        -- if the open failed, then next_line remains as io.read
        io.write(status,". Reading from stdin.\n")
      else
        next_line = function() return f:read() end
      end
    end
    local linenum = 0
    local line = next_line()
    while line do
      -- for each line
      linenum = linenum + 1
      -- if linenum > 1 then we've read a new line
      if linenum > 1 then send(new_token("NEWLINE", "")) end
      -- io.write("\t\t", ("%5d "):format(linenum), line, "\n") -- TODO
      -- start at index 1 and try to match patterns
      local i = 1
      while i <= line:len() do
        for _,f in ipairs(lex_items) do
          local match = f(line, i)
          if match then
            send(match)
            i = i + match.length-1
            break
          end
        end
        i = i + 1
      end
      line = next_line()
    end
  end)
end

-- parse tokens from the lexer
-- we need two tokens of lookahead
function parser(lexer)
  local prev_token = nil
  local token = receive(lexer)
  local token1 = receive(lexer)
  local token2 = receive(lexer)
  -- functions to look ahead at and consume tokens from the lexer
  function tag(...)
    if token then
      for _,t in ipairs({...}) do
        if token.tag == t then return true end
      end
    end
    return false
  end
  function peek(tag1, tag2)
    if tag1 and tag2 and token1 and token2 then
      if token1.tag == tag1 and token2.tag == tag2 then return true end
    elseif tag1 and token1 then
      if token1.tag == tag1 then return true end
    end
    return false
  end
  function take()
    prev_token = token
    token = token1
    token1 = token2
    token2 = receive(lexer) or new_token("EOF")
    return token
  end

  -- functions for the lowest level concrete syntax items
  -- white, ink
  -- white captures contiguous whitespace
  -- returns the whitespace, the token before the whitespace
  function make_white()
    local s = ""
    local p = prev_token
    while tag("WHITE", "BREAK") do
      if tag("BREAK") then
        -- consume newlines, breaks, and all leading whitespace
        while tag("WHITE", "BREAK", "NEWLINE") do
          take()
        end
      elseif tag("WHITE") then
        s = s..token.value
        take()
      end
    end
    if s == "" then return nil end
    return s, p
  end
  -- ink captures contiguous black: names and punctuation
  -- the parser has no trouble with colons inside ink
  function make_ink()
    local s = ""
    while tag("NAME", "NUMBER", "PUNCT", "COLON", "ESCAPE") do
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
    -- when formulating a literal, keep whitespace at the end if the
    -- the next token is something special
    if w and tag("NAME", "NUMBER", "PUNCT", "LPAREN", "ESCAPE") then
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
    if tag("LPAREN") and peek("NAME") then
      take() -- consume left paren
      r = make_name()
      if not tag("RPAREN") then
        --print("Error. Expecting ')' and found "..token.value)
        return nil
      end
      take() -- consume right paren
    end
    return r and ref(r) or nil
  end
  -- weight is [n] or [n-n']
  -- returns an int weight
  function make_weight()
    local w = 1
    if tag("PUNCT") and peek("NUMBER") and token.value == "[" then
      take() -- consume [
      local min = tonumber(token.value)
      take() -- number
      -- if there's a hyphen then we have a range; otherwise the weight is one
      if tag("PUNCT") and peek("NUMBER") and token.value == "-" then
        take() -- hyphen
        local max = tonumber(token.value)
        take() -- number
        w = math.abs(max-min)+1
      end
      if tag("PUNCT") and token.value == "]" then take() end
      make_white()
    end
    return w
  end
  -- resolution is name <- inlineitemlist
  -- returns a Res abstract syntax node or nil
  function make_Hold()
    if not peek("LARROW") then
      return nil
    end
    local name = make_name()
    if not name then
      --print("Error making Res: could not find NAME")
      return nil
    end
    -- match : and then consume whitespace
    take()
    make_white()
    local items = make_inlineitemlist()
    return res(name, items)
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
    -- if there's a trailing comment, consume it
    if tag("COMMENT") then take() end
    -- if an item is followed by a newline or EOF, then that's it
    -- otherwise, it's followed by another item
    if tag("NEWLINE", "EOF") then
      return i
    else
      local item = make_Item()
      if item then
        -- if we saw a ) before this item then keep the whitespace as a literal
        if previous and previous.tag == "RPAREN" then
          local ws = lit(w)
          i = mix(i, ws)
        end
        return mix(i, item)
      else
        return i
      end
    end
  end
  function make_Formatted_Item()
    local i = nil
    -- ref or lit
    i = make_reference() or make_literal()
    if not i then
      --print("Error making item: could not find literal or reference")
      return nil
    end
    -- whitespace between items is sometimes significant
    local w, previous = make_white()
    -- if there's a trailing comment, consume it
    if tag("COMMENT") then take() end
    -- if an item is followed by EOF, then that's it
    if tag("EOF") then return i end
    -- if followed by a newline, then convert that to a space
    if tag("NEWLINE") then
      w = " "
      previous = token
      take()
    end
    local item = make_Formatted_Item()
    if item then
      -- if we saw a ) before this item then keep the whitespace as a literal
      if previous and
         (previous.tag == "RPAREN" or previous.tag == "NEWLINE") then
        local ws = lit(w)
        i = mix(i, ws)
      end
      return mix(i, item)
    else
      return i
    end
  end
  -- inlineitemlist
  function make_inlineitemlist()
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
        --print("Error making itemlist: could not find item")
      else
        items[#items+1] = item
      end
    end
    return items
  end
  -- listitemlist
  -- TODO quite similar to inlineitemlist; could take sep as param?
  function make_listitemlist()
    local w = make_weight()
    local i = make_Item()
    if not i then
      --print("Error making itemlist: could not find item")
      return nil
    end
    local items = {}
    for n=1,w do items[#items+1] = i end
    while tag("NEWLINE") do
      -- match separator and consume whitespace
      take()
      make_white()
      -- ignore comments or rule lines inside of the list itemlist
      while tag("COMMENT", "1RULE") do
        take() -- take the comment/rule
        take() -- take the newline
        make_white()
      end
      -- a second newline ends the list itemlist
      if tag("NEWLINE") then break end
      w = make_weight()
      local item = make_Item()
      if not item then
        --print("Error making itemlist: could not find item")
      else
        for n=1,w do items[#items+1] = item end
      end
    end
    return items
  end
  -- formatteditemlist
  function make_formatteditemlist()
    local w = make_weight()
    local i = make_Formatted_Item()
    if not i then
      --print("Error making itemlist: could not find item")
      return nil
    end
    local items = {}
    for n=1,w do items[#items+1] = i end
    while tag("1RULE") do
      -- match separator and consume whitespace
      take()
      make_white()
      take() -- take the newline after the rule
      make_white()
      -- a second newline ends the formatted itemlist
      if tag("NEWLINE") then break end
      w = make_weight()
      local item = make_Formatted_Item()
      if not item then
        --print("Error making itemlist: could not find item")
      else
        for n=1,w do items[#items+1] = item end
      end
    end
    return items
  end
  -- a List is a definition
  -- returns a Def abstract sytnax node or nil
  function make_List()
    if not (peek("COLON") or
            peek("NEWLINE", "1RULE") or
            peek("NEWLINE", "2RULE")) then
      return nil
    end
    local name = make_name()
    if not name then
      --print("Error making List: could not find NAME")
      return nil
    end
    -- take : or \n and then consume whitespace
    take()
    make_white()
    local items = nil
    if tag("1RULE") then
      take() -- rule
      take() -- \n
      make_white()
      items = make_listitemlist()
    elseif tag("2RULE") then
      take() -- rule
      take() -- \n
      make_white()
      items = make_formatteditemlist()
    else
      items = make_inlineitemlist()
    end
    return def(name, items)
  end

  -- parse the token stream and built a list of statements
  local statements = {}
  while token do
    -- a statement is a list definition or an item
    -- TODO or maybe just whitespace
    local s = make_List() or make_Hold() or make_Item()
    if s then
      statements[#statements+1] = s
    else
      -- consume whatever it is
      -- print("Could not make a statement starting with *"..token.value.."*")
      take()
    end
    if tag("EOF") then break end
  end
  return statements
end

-- create an abstract syntax node
Node = {}
local mt = {}
function Node.new(tag, value)
  local node = {tag=tag, value=value}
  setmetatable(node, mt)
  return node
end
function Node.tostring(n)
  local s = "("..n.tag.." "
  if n.tag == "Ref" or n.tag == "Res" or n.tag == "Lit" then
    s = s..n.value
  elseif n.tag == "Mix" then
    for _,item in ipairs(n.value) do
      s = s.." "..Node.tostring(item)
    end
  elseif n.tag == "Def" then
    -- n.value[1] is name, n.value[2] is items
    s = s..n.value[1].." "
    for _,item in ipairs(n.value[2]) do
      s = s.." "..Node.tostring(item)
    end
  end
  return s..")"
end
mt.__tostring = Node.tostring

-- abstract syntax
-- constructors
-- List
function def(name, items) return Node.new("Def", {name, items}) end
-- Item
function ref(name) return Node.new("Ref", name) end
function lit(literal) return Node.new("Lit", literal) end
function mix(item1, item2) return Node.new("Mix", {item1, item2}) end
-- Hold
function res(name, items) return Node.new("Res", {name, items}) end

state = {}
math.randomseed(os.time())
-- math.randomseed(0) -- TODO!
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
  -- res populates the state table by evaluating something from the item list
  elseif tag == "Res" then
    local name = v[1]
    local list = v[2]
    if #list == 0 then return nothing end
    state[name] = {lit(eval(list[math.random(#list)]))}
  -- lit. eval to itself
  elseif tag == "Lit" then
    v = v:gsub("\\n", "\n")
    v = v:gsub("\\", "")
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

function printstate()
  io.write('{')
  for k,v in pairs(state) do io.write(k,', ') end
  io.write('}\n')
end

-- invocat!
local statements = parser(lexer())
for _,s in ipairs(statements) do
  r = eval(s)
  if r then print(r) end
end
-- print(os.clock())

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
  print(eval(r2))
end
--]]

-- tostring tests
--[[
print("tostring --------")
local test = def('wizard', {lit("rabbit")})
print(test)
print(recurse)
print(deer) -- deer
print(r) -- animux
print(mr) -- x
print(animux)
print("end tostring --------")
--]]
