module Bio

import ..Bufio, ..readbyte, ..readuntil!, ..tostring, ..reserve!, ..trimret

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

end # module Bio
