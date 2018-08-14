#!/usr/bin/env julia

include("../src/Klib.jl")

function main(args)
	if length(args) == 0 return end
	fx = Klib.FastxReader(Klib.GzFile(args[1]))
	ln, ls, lc, lq = 0, 0, 0, 0
	while (r = read(fx)) != nothing
		ln += lastindex(r.name)
		lc += lastindex(r.comment)
		ls += lastindex(r.seq)
		lq += lastindex(r.qual)
	end
	println("$ln\t$lc\t$ls\t$lq")
end

@time main(ARGS)
