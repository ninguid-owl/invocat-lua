--
-- Read from standard input and output a Markov data structure as an
-- Invocat file.
--
local pattern =  "%S+"

function allwords ()
  local line = io.read()
  local pos = 1
  return function ()
    while line do
      local s, e = string.find(line, pattern, pos)
      if s then
        pos = e + 1
        return string.sub(line, s, e)
      else
        line = io.read()
        pos = 1
      end
    end
    return nil
  end
end

function prefix (w1, w2)
  return w1 .. " " .. w2
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


local MAXGEN = 200
local NOWORD = "NIL"

math.randomseed(os.time())

-- build table
local w1, w2 = NOWORD, NOWORD
for w in allwords() do
  insert(prefix(w1, w2), w)
  w1 = w2; w2 = w;
end
insert(prefix(w1, w2), NOWORD)

-- mod the original to start anywhere
-- create keys so we can start anywhere
--local keys, i = {}, 1
--for k,_ in pairs(statetab) do
--  keys[i] = k
--  i = i+1
--end

-- print Invocat statements
-- TODO: escape colons parens etc
print("-- definitions")
for k,v in pairs(statetab) do
  -- pull the two separate words out of the key
  local idx, w1, w2
  idx = k:find(" ")
  w1 = k:sub(0, idx)
  w2 = k:sub(idx+1)
  local val = w2.." ("..w2.." "..v[1]..")"
  if #v>1 then 
    for i=2,#v do
      val = val.."|"..w2.." ("..w2.." "..v[i]..")"
    end
  end
  print(k..": "..val)
end

-- begin generation with (NOWORD NOWORD)
print("-- expressions")
print("("..NOWORD.." "..NOWORD..")")

---- generate
--startkey = keys[math.random(1, #keys)]
--s, e = startkey:find(pattern, 1)
--w1 = startkey:sub(s, e)
--w2 = startkey:sub(e+2, -1)
--for i=1, MAXGEN do
--  local list = statetab[prefix(w1, w2)]
--  local r = math.random(#list)
--  local nextword = list[r]
--  if nextword == NOWORD then return end
--  io.write(nextword, " ")
--  w1 = w2; w2 = nextword
--end
--io.write("\n")

