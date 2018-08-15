#!/usr/bin/env julia

include("../src/Klib.jl")

using GZip
using CodecZlib

Base.eof(fp::Klib.GzFile) = ccall((:gzeof, "libz"), Cint, (Ptr{Cvoid},), fp.fp) != 0 ? true : false
Base.read(fp::Klib.GzFile, ::Type{UInt8}) = UInt8(ccall((:gzgetc, "libz"), Cint, (Ptr{Cvoid},), fp.fp))

function test_klib(fn) # 24.487621 seconds (80.00 M allocations: 7.340 GiB, 0.88% gc time) 24.34user 0.44system 0:24.82elapsed 99%CPU (0avgtext+0avgdata 181300maxresident)k
	println("Method: Klib.realine")
	sum, nl = 0, 0
	r = Klib.Bufio(Klib.GzFile(fn))
	while (s = readline(r)) != nothing
		sum += lastindex(s)
		nl += 1
	end
	return sum, nl
end

function test_base(fn) # 212.494007 seconds (322.63 M allocations: 21.697 GiB, 0.29% gc time) 209.06user 0.59system 3:29.88elapsed 99%CPU (0avgtext+0avgdata 183456maxresident)k
	println("Method: Base.eachline")
	sum, nl = 0, 0
	for s in eachline(Klib.GzFile(fn))
		sum += lastindex(s)
		nl += 1
	end
	return sum, nl
end

function test_pipe(fn) # 54.236479 seconds (280.64 M allocations: 18.202 GiB, 1.98% gc time) 83.33user 2.76system 0:52.41elapsed 164%CPU (0avgtext+0avgdata 188672maxresident)k
	println("Method: pipe")
	sum, nl = 0, 0
	io = occursin(r"\.gz$", fn) ? open(`gzip -dc $fn`) : open(fn)
	for s in eachline(io)
		sum += lastindex(s)
		nl += 1
	end
	return sum, nl
end

function test_gzip(fn) # 290.985147 seconds (322.63 M allocations: 21.696 GiB, 0.26% gc time) 293.10user 0.77system 4:54.19elapsed 99%CPU (0avgtext+0avgdata 193444maxresident)k
	println("Method: GZip")
	sum, nl = 0, 0
	for s in eachline(GZip.open(fn))
		sum += lastindex(s)
		nl += 1
	end
	return sum, nl
end

function test_cz(fn) # 26.424243 seconds (160.33 M allocations: 12.437 GiB, 2.14% gc time) 27.31user 0.51system 0:27.91elapsed 99%CPU (0avgtext+0avgdata 193920maxresident)k
	println("Method: CodecZlib")
	sum, nl = 0, 0
	for s in eachline(GzipDecompressorStream(open(fn)))
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
		elseif method == "pipe"
			@time sum, nl = test_pipe(args[1])
		elseif method == "gzip"
			@time sum, nl = test_gzip(args[1])
		elseif method == "cz"
			@time sum, nl = test_cz(args[1])
		else
			write(stderr, "ERROR: unknown method \"$method\"\n")
			return
		end
		println("Number of lines: $nl")
		println("Number of bytes in lines: $sum")
	else
		println("Usage: julia test-rl.jl [-m klib|base] <file>")
	end
end

main(ARGS)
