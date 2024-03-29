Invocat
=======
A nondeterministic, generative programming language for text by C & M Antoun.
2015-03-18


Contents
--------
    invocat.lua   -- The Invocat lexer, parser, and interpreter
    README        -- This file

    tests/
        test.inv          -- Simple tests
        the-whale.inv     -- Markov example trained on some of Moby Dick
        treasures.inv     -- A treasure generator
        shipwrecked.inv   -- A random table

    misc/
        train-markov.lua  -- Convert an input file to an Invocat Markov chain
        the-whale.txt     -- Text file used to generate the-whale.inv


The Language
------------
Invocat is a language for randomly generating from grammars, which take the form
of lists. There are three ways to make a list. Here are some illustrative
examples:

    -- this style is convenient for short lists
    -- a name followed by a colon and then a list of items

    adj: warm | fuzzed out | most impenetrable | lacerating | (adj), (adj)

    -- this style lets you put one item on each line
    -- a name, underlined with at least three ---

    object
    ------
    thought on an obscure subject
    musing
    reverberation of (something)
    memory of (something)
    drone

    -- and this style allows you to work with long lines
    -- a name, underlined with at least three === and items
    -- separated by at least three ---

    something
    ===================================================
    A (adj) (object) at a most inopportune time, taking
    into account nothing of the present circumstances
    ---------------------------------------------------
    Without any warning, a (adj), dull, (object)
    overtakes your senses and leaves you in a most
    indescribable mood
    ---------------------------------------------------
    How did it even happen? Sitting in the drawing room,
    a (adj) sensation, a (object), though without
    attachment

The second two styles also allow you specify weights for the items, like below.
The spacing and alignment aren't important, and the weights are optional per
item.

    goblin_attack
    -------------
    [1-3] short sword
    [4-5] shield bash
      [6] firebomb!

You get (random) results from lists with references, which are just the list
names in parentheses. For example, the next line just picks something from the 'something'
list that we defined above and adds a period to the end. Notice that its
definition refers to other lists. If you refer to a list that's not defined, you
get the empty string.

    (something).  -- this is just a reference
    (nothing)     -- this doesn't produce anything

If you want to refer to the same thing more than once,

    certain_adj <- (adj)
    I am sure it was (certain_adj): it was definitely (certain_adj).



Usage
-----
Invocat is written in Lua (5.2.0) and requires a Lua interpreter. If a file name
argument is provided, the file will be executed as an Invocat program. With no
arguments, Invocat will read from standard input.

    $ ./invocat.lua [file]

To generate endless treasures using the world's longest Invocat program:

    $ ./invocat.lua tests/treasures.inv

To run the Markov text generation example:

    $ ./invocat.lua tests/the-whale.inv

