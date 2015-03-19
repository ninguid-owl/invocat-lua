#! /usr/bin/env lua

-- Read from standard input or a file and print a Markov data structure in the
-- form of Invocat definitions. Also print a starting expression to kick off
-- the generation.

local RANDOM_START = false    -- begin generation midstream?
local pattern =  "%S+"        -- take all non-whitespace as a word

function allwords ()
  local next_line = io.read
  if arg[1] then
    local f = assert(io.open(arg[1], "rb"))
    next_line = function () return f:read() end
  end
  local line = next_line()
  local pos = 1
  return function ()
    while line do
      local s, e = string.find(line, pattern, pos)
      if s then
        pos = e + 1
        return string.sub(line, s, e)
      else
        line = next_line()
        pos = 1
      end
    end
    return nil
  end
end

function prefix (w1, w2)
  return w1 .. "_" .. w2
end

local statetab = {}

function insert (index, value)
  local list = statetab[index]
  if list == nil then
    statetab[index] = {value}
  else
    list[#list + 1] = value
  end
end

local NOWORD = ""

-- build table
local w1, w2 = NOWORD, NOWORD
for w in allwords() do
  insert(prefix(w1, w2), w)
  w1 = w2; w2 = w;
end
insert(prefix(w1, w2), NOWORD)

-- print Invocat statements
print("-- definitions")
for k,v in pairs(statetab) do
  -- pull the two separate words out of the key
  local idx, w1, w2
  idx = k:find("_")
  w1 = k:sub(0, idx)
  w2 = k:sub(idx+1)
  local val = w2.." ("..w2.."_"..v[1]..")"
  if #v>1 then 
    for i=2,#v do
      val = val.."|"..w2.." ("..w2.."_"..v[i]..")"
    end
  end
  print(k..": "..val)
end

print("-- expressions")
if RANDOM_START then
  -- create keys from which to choose at random
  local keys, i = {}, 1
  for k,_ in pairs(statetab) do
    keys[i] = k
    i = i+1
  end
  math.randomseed(os.time())
  print("("..keys[math.random(#keys)]..")")
else
  -- begin generation with (NOWORD NOWORD) which will produce
  -- the opening word from the training document
  print("("..NOWORD.."_"..NOWORD..")")
end
