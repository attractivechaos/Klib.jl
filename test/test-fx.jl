include("../src/Klib.jl")

function main(args)
	if length(args) == 0 return end
	fx = Klib.Bio.FastxReader{Klib.GzFile}(Klib.GzFile(args[1]))
	while (r = read(fx)) != nothing
		c = r.qual != "" ? "@" : ">"
		print(c, r.name)
		if r.comment != "" print(" ", r.comment) end
		print("\n")
		println(r.seq)
		if r.qual != ""
			println("+")
			println(r.qual)
		end
	end
end

main(ARGS)
