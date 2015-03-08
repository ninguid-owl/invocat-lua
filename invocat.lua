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
  --local _literal = new_lex("_LITERAL", '"[^"]*"') -- TODO this is fake
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
                    --or _literal(line, i)
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

  -- functions for the lowest level concrete syntax items
  -- white, ink
  -- white captures contiguous white space
  function make_white()
    local s = ""
    while tag("WHITE") do
      s = s..token.value
      take()
    end
    if s == "" then return nil end
    return s
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
  -- returns a Lit
  function make_literal(r)
    local l = make_ink()
    -- if we can't build up the literal, return what have so far
    if not l then return r end
    -- if we passed anything in recursively, then build on that
    --if r then for k,v in pairs(r) do print("r "..k.." "..v) end end -- TODO
    l = r and r.value..l or l
    local w = make_white()
    -- TODO parenl?
    if w and (tag("NAME") or tag("PUNCT") or tag("PARENL")) then
      l = lit(l..w)
      l = make_literal(l)
    else
      l = lit(l)
      --print('found a literal followd by ('..l.tag.." "..l.value..")") -- TODO
    end
    print('lit *'..l.value..'*')
    return l
  end

  -- reference is (name)
  -- returns a Ref
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
      print('ref '..r)
    end
    --end
    return r and ref(r) or nil
  end

  -- an item is a reference, literal, or mix of items
  -- returns Ref, Lit, or Mix
  function make_Item()
    local i = nil
    -- ref or lit
    i = make_reference() or make_literal()
    if not i then
      --print("Error making item: could not find literal or reference")
      return nil
    end

    -- TODO ignore whitespace between items ?
    -- how to do that selectively?
    -- another (adj) festival
    -- a ref next to a lit, or vice versa, -> keep the white between
    make_white()

    -- if an item is followed by a newline or EOF, then that's it
    -- otherwise, it's followed by another item
    if tag("NEWLINE") or tag("EOF") then
      return i
    else
      --print('found a ref or lit, then ('..i.tag.." "..i.value..")") -- TODO
      local item = make_Item()
      if item then return mix(i, item) else return i end
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
      take()
      local item = make_Item()
      if not item then
        --print("Error making itemlist: could not find item")
        return nil
      end
      items[#items+1] = item
    end
  end

  -- return a List
  function make_List()
    if not peek("COLON") then
      print('in make_List, we have ('..token.tag..'), ('..next_token.tag..' '..next_token.value..')')
      return nil
    end
    local name = make_name()
    if not name then
      --print("Error making List: could not find NAME")
      return nil
    end
    -- match : and then consume whitespace -- TODO
    take()
    make_white()
    local items = make_itemlist()
    print('def '..name)
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
      -- consume whitespace or whatever it is
      --print("Could not make a statement starting with *"..token.value.."*")
      take()
    end
    if tag("EOF") or peek("EOF") then break end
    --io.write("(", token.tag, " ", token.value, ")", "\n")
  end
  return statements
end

------------------------------------------------------------------- testing
-- create an abstract syntax node
-- TODO a display function to print s-expression. and for tokens, too
function node(tag, value) return {tag=tag, value=value} end

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
  -----------------------------------------------------------------------------
  io.write("(",tag," ")
  --for _,val in ipairs(v) do
    --io.write("[",val,"]")
  --end
  io.write(")\n")
  -----------------------------------------------------------------------------
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
    local t1 = eval(v[1]) -- or nothing
    local t2 = eval(v[2]) -- or nothing
    return t1..t2
  elseif tag == "Def" then
    local name = v[1]
    local list = v[2]
    state[name] = list
    -- return ???
  end
end

-- tests
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


local statements = parser(lexer())
for _,s in ipairs(statements) do
  r = eval(s)
  if r then print('> ['..s.tag..'] '..r)
  else print('> ['..s.tag..']')
  end
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
