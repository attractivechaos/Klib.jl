#!/usr/bin/env julia

include("../src/Klib.jl")

function test_klib(fn)
	println("Method: Klib.realine")
	sum, nl = 0, 0
	r = Klib.Bufio(Klib.GzFile(fn))
	while (s = readline(r)) != nothing
		sum += lastindex(s)
		nl += 1
	end
	return sum, nl
end

function test_base(fn)
	println("Method: Base.eachline")
	sum, nl = 0, 0
	for s in eachline(fn)
		sum += lastindex(s)
		nl += 1
	end
	return sum, nl
end

function main(args)
	method = "klib"
	for (opt, arg) in Klib.getopt(ARGS, "-m:")
		if opt == 'm' method = arg end
	end
	if length(args) > 0
		if method == "klib"
			@time sum, nl = test_klib(args[1])
		elseif method == "base"
			@time sum, nl = test_base(args[1])
		else
			write(stderr, "ERROR: unknown method \"$algo\"\n")
			return
		end
		println("Number of lines: $nl")
		println("Number of bytes in lines: $sum")
	else
		println("Usage: julia test-rl.jl [-m klib|base] <file>")
	end
end

main(ARGS)
