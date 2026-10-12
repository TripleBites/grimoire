# M1 boot check: runs Janet inside grimoire and imports a module from src/lib.
(import grimoire/hello)

(print "grimoire is running Janet " janet/version)
(print (hello/greet "owner"))
