module Klib

export Getopt, getopt, GzFile, close, Bufio, readuntil!, readbyte

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

include("Bio.jl")

end # module Klib
