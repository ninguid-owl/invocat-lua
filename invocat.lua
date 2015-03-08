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
  -- and produces a token
  -- (and executes f)
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
  local _literal = new_lex("_LITERAL", '"[^"]*"')
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
      if linenum > 1 then send(new_token("NEWLINE", "")) end
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
  function peek(tag)
    if next_token.tag == tag then return true end
    return false
  end
  function take()
    token = next_token
    next_token = receive(lexer) or new_token("EOF")
    return token
  end
  while token do
    -- this is the advance function: get next token
    -- if you need a look-ahead mechanism, that will take some thought
    --io.write("(", token.tag, " ", token.value, ")", "\n")
    if token.tag == "COMMENT" then
      --print("Comment: " .. token.value)
    elseif token.tag == "NAME" and peek("COLON") then
      print("found def")
      --local s = makeDef()
    elseif token.tag == "EOF" then
      print("Found EOF")
    --  local s = makeItem()
    end
    --if s then print("Got a dang statement: " .. s) end
    if peek("EOF") then
      break
    end
    take()
    --io.write("(", token.tag, " ", token.value, ")", "\n")
  end
end




-- abstract syntax
-- Term ::= List [Term] | Literal string | Mix Term Term
-- term = {tag="List", value={Term, ...}} or otherwise
-- this is where Haskell is awesome
function eval(term)
  local v = term.value
  if not v then return nil end
  -- list: randomly pick an element of the list
  if term.tag == "List" then
    print("length of v "..#v)
    if #v == 0 then return "" end -- TODO test
    return eval(v[math.random(#v)])
  elseif term.tag == "Literal" then
    return v
  elseif term.tag == "Mix" then
    local t1 = eval(v[1])
    local t2 = eval(v[2])
    if t1 and t2 then return t1..t2
    else return "" end
  end
end

function list(name, terms) return {tag="List", name=name, value=terms} end
function ref(name) return {tag="Ref", name=name} end
function literal(string) return {tag="Literal", value=string} end
function mix(term1, term2) return {tag="Literal", value={term1, term2}} end

-- tests
local hihi = literal("hihihi")
local animux = list("animux", {literal("hihihi")})
--print(eval(hihi))
--print(eval(animux))

state = {}

parser(lexer())

-- use coroutines to set up a producer/consumer model for the lexer and the
-- parser
-- the lexer reads input and returns tokens, which 
-- are tables that have tag and value fields (and others?)
-- the parser requests tokens from the lexer and builds an AST
-- TODO how is the AST represented here?
-- i think once the lexer returns an end of program token then the parser
-- finalizes the AST
-- finally, we evaluate the AST
