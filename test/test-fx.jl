include("../src/Klib.jl")

function main(args)
	if length(args) == 0 return end
	fx = Klib.FastxReader(Klib.GzFile(args[1]))
	while Klib.read!(fx) >= 0
		c = fx.qual != "" ? "@" : ">"
		print(c, fx.name)
		if fx.comment != "" print(" ", fx.comment) end
		print("\n")
		println(fx.seq)
		if fx.qual != ""
			println("+")
			println(fx.qual)
		end
	end
end

main(ARGS)
