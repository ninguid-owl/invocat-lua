#! /usr/local/bin/lua
-- a lexer ...

-- utility functions for working with coroutines
function receive(producer)
  local status, value = coroutine.resume(producer)
  return value
end

function send(x) coroutine.yield(x) end

-- definition of a token
-- has a tag, a value, a length
function new_token(tag, value)
  local token = {}
  token.tag = tag
  token.value = value
  token.length = value:len()
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
local comment = new_lex("COMMENT", '[-][-].*$')
local punctuation = new_lex("PUNCT", '%p') -- TODO all punct! check late
local whitespace = new_lex("WHITE", '%s')

-- read file
-- returns a coroutine that spits out tokens
function lexer()
  return coroutine.create(function()
    local f = assert(io.open(arg[1], "rb"))
    local linenum = 0
    while true do
      -- for each line
      local line = f:read(); if not line then break end -- TODO end token?
      linenum = linenum + 1
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
    end
  end)
end

function parser(lexer)
  while true do
    -- this is the advance function: get next token
    local x = receive(lexer)
    if not x then break end
    io.write("(", x.tag, " ", x.value, ")", "\n")
  end
end

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
