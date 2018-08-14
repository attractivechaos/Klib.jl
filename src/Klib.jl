module Klib

export Getopt, getopt, GzFile, close, Bufio, readuntil!

#
# Getopt iterator
#
struct Getopt
	args::Array{String}
	ostr::String
end

function Base.iterate(g::Getopt, (pos, ind) = (1, 1))
	if g.ostr[1] == '-' # allow options to appear after main arguments
		while ind <= length(g.args) && g.args[ind][1] != '-'
			ind += 1
		end
	end
	if ind > length(g.args) || g.args[ind][1] != '-' return nothing end
	if g.args[ind] == "-" return nothing end
	if g.args[ind] == "--" # actually, Julia will always filter out "--" in ARGS. Ugh!
		deleteat!(g.args, ind)
		return nothing
	end
	if pos == 1 pos = 2 end
	optopt, optarg = g.args[ind][pos], ""
	pos += 1
	i = findfirst(isequal(optopt), g.ostr)
	if i == nothing # unknown option
		optopt = '?'
	else
		if i < length(g.ostr) && g.ostr[i + 1] == ':' # require argument
			if pos <= length(g.args[ind])
				optarg = g.args[ind][pos:end]
			else
				deleteat!(g.args, ind)
				if ind <= length(g.args)
					optarg = g.args[ind]
				else # missing argument
					return ((optopt, ""), (pos, ind))
				end
			end
			pos = length(g.args[ind]) + 1
		end
	end
	if pos > length(g.args[ind])
		deleteat!(g.args, ind) # FIXME: can be slow when ostr[1] == '-'
		pos = 1
	end
	return ((optopt, optarg), (pos, ind))
end

getopt(args::Array{String}, ostr::String) = Getopt(args, ostr)

#
# ByteBuffer
#
mutable struct ByteBuffer <: AbstractVector{UInt8}
	a::Ptr{UInt8}
	m::UInt64

	function ByteBuffer()
		x = new(C_NULL, 0)
		finalizer(destroy!, x)
		return x
	end
end

function reserve!(b::ByteBuffer, z::UInt64)
	if z > b.m
		x = z - 1; x |= x >> 1; x |= x >> 2; x |= x >> 4; x |= x >> 8; x |= x >> 16; x |= x >> 32; x += 1
		b.m = (x<<1) + (x<<2) >= z ? (x<<1) + (x<<2) : x
		b.a = ccall(:realloc, Ptr{Cvoid}, (Ptr{Cvoid}, Csize_t), b.a, b.m)
	end
end

function destroy!(b::ByteBuffer)
	ret = ccall(:free, Cint, (Ptr{Cvoid},), b.a)
	b.a, b.m = C_NULL, 0
	return ret
end

tostring(b::ByteBuffer, n::Int) = String(unsafe_wrap(Vector{UInt8}, b.a, n))

#
# GzFile
#
mutable struct GzFile <: IO
	fp::Ptr{Cvoid}

	function GzFile(fn::String, mode = "r")
		x = ccall((:gzopen, "libz"), Ptr{Cvoid}, (Cstring, Cstring), fn, mode)
		y = x == C_NULL ? nothing : new(x)
		if y != nothing finalizer(Base.close, y) end
		return y
	end
end

Base.readbytes!(fp::GzFile, buf::Vector{UInt8}) = ccall((:gzread, "libz"), Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Cuint), fp.fp, buf, length(buf))

function Base.close(fp::GzFile)
	ret = fp.fp != C_NULL ? ccall((:gzclose, "libz"), Cint, (Ptr{Cvoid},), fp.fp) : -1
	fp.fp = C_NULL
	return ret
end

#
# Bufio
#
mutable struct Bufio{T<:IO} <: IO
	fp::T
	start::Int
	len::Int
	iseof::Bool
	buf::Vector{UInt8}
	bb::ByteBuffer

	Bufio{T}(fp::T, bufsize = 0x10000) where {T<:IO} = new{T}(fp, 1, 0, false, Vector{UInt8}(undef, bufsize), ByteBuffer())
end

function Base.readbytes!(fp::Bufio{T}, buf::Vector{UInt8}, len=length(buf)) where {T<:IO}
	if fp.iseof && fp.start > fp.len return -1 end
	offset = 1
	while len > fp.len - (fp.start - 1)
		l = fp.len - (fp.start - 1)
		@inbounds copyto!(buf, offset, fp.buf, fp.start, l)
		len -= l
		offset += l
		fp.start, fp.len = 1, Base.readbytes!(fp.fp, fp.buf)
		if fp.len < length(fp.buf) fp.iseof = true end
		if fp.len == 0 return offset - 1 end
	end
	@inbounds copyto!(buf, offset, fp.buf, fp.start, len)
	fp.start += len
	return offset - 1 + len
end

function readbyte(r::Bufio{T}) where {T<:IO}
	if r.iseof && r.start > r.len return -1 end
	if r.start > r.len
		r.start, r.len = 1, Base.readbytes!(r.fp, r.buf)
		if r.len < length(r.buf) r.iseof = true end
		if r.len == 0 return -1 end
	end
	c = r.buf[r.start]
	r.start += 1
	return c
end

trimret(buf::ByteBuffer, n) = n > 0 && unsafe_load(buf.a, n) == 0x0d ? n - 1 : n

function readuntil!(r::Bufio{T}, delim = -1, offset = 0, keep::Bool = false) where {T<:IO}
	if r.start > r.len && r.iseof return -1 end
	n = 0
	while true
		if r.start > r.len
			if r.iseof == false
				r.start, r.len = 1, Base.readbytes!(r.fp, r.buf)
				if r.len == 0 r.iseof = true; break end
				if r.len < 0 r.iseof = true; return -3 end
			else
				break
			end
		end
		x = r.len + 1
		if delim == -1 # use '\n' as the delimitor
			for i = r.start:r.len
				@inbounds if r.buf[i] == 0x0a x = i; break end
			end
		elseif delim == -2 # use ' ', '\t' or '\n' as the delimitor
			for i = r.start:r.len
				@inbounds if r.buf[i] == 0x20 || r.buf[i] == 0x09 || r.buf[i] == 0x0a x = i; break end
			end
		else
			for i = r.start:r.len
				@inbounds if r.buf[i] == delim x = i; break end
			end
		end
		l = keep && x <= r.len ? x - r.start + 1 : x - r.start
		reserve!(r.bb, UInt64(offset + n + l))
		unsafe_copyto!(r.bb.a + offset + n, pointer(r.buf, r.start), l)
		n += l
		r.start = x + 1
		if x <= r.len break end
	end
	if (delim == -1 || delim == -2) && !keep n = trimret(r.bb, n) end # remove trailing '\r' if present
	return n == 0 && r.iseof ? -1 : n
end

function Base.readline(r::Bufio{T}) where {T<:IO}
	n = readuntil!(r)
	n >= 0 ? tostring(r.bb, n) : nothing
end

#
# FastxReader
#
mutable struct FastxReader{T<:IO}
	r::Bufio{T}
	last::UInt8
	errno::Int

	FastxReader{T}(io::T) where {T<:IO} = new{T}(Bufio{T}(io), 0, 0)
end

mutable struct FastxRecord
	name::String
	seq::String
	qual::String
	comment::String
end

function Base.read(f::FastxReader{T}) where {T<:IO}
	if f.last == 0 # then jump to the next header line
		while (c = readbyte(f.r)) >= 0 && c != 0x3e && c != 0x40 end # 0x3e = '>', 0x40 = '@'
		if c < 0 return nothing end
		f.last = c
	end # else: the first header char has been read in the previous call
	name = comment = seq = "" # reset all members
	n = readuntil!(f.r, -2, 0, true)
	if n < 0 return nothing end # normal exit: EOF
	if unsafe_load(f.r.bb.a, n) == 0x0a # end-of-line; no comments
		n = trimret(f.r.bb, n - 1)
		name = tostring(f.r.bb, n)
	else # there are FASTX comments
		name = tostring(f.r.bb, n - 1)
		n = readuntil!(f.r)
		comment = tostring(f.r.bb, n)
	end
	ls = 0
	while (c = readbyte(f.r)) >= 0 && c != 0x3e && c != 0x40 && c != 0x2b # 0x2b = '+'
		if c == 0x0a continue end # skip empty lines
		reserve!(f.r.bb, UInt64(ls + 1))
		unsafe_store!(f.r.bb.a, c, ls + 1) # write the first character
		ls += 1
		ls += readuntil!(f.r, -1, ls) # read the rest of the line
	end
	if c == 0x3e || c == 0x40 f.last = c end # the first header char has been read
	seq = tostring(f.r.bb, ls) # sequence read
	@assert ls == lastindex(seq) # guard against UTF-8
	if c != 0x2b return FastxRecord(name, seq, "", comment) end # FASTA
	while (c = readbyte(f.r)) >= 0 && c != 0x0a end # skip the rest of '+' line
	if c < 0 f.errno; return nothing end # error: no quality string
	lq = 0
	while lq < ls
		n = readuntil!(f.r, -1, lq)
		if n < 0 break end
		lq += n
	end
	f.last = 0
	if lq != ls f.errno = -2; return nothing end # error: qual string is of a different length
	qual = tostring(f.r.bb, lq) # quality read
	@assert lq == lastindex(qual) # guard against UTF-8
	return FastxRecord(name, seq, qual, comment)
end

end # module Klib
