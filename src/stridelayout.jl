
"""
    offsets(A) -> Tuple

Returns offsets of indices with respect to 0. If values are known at compile time,
it should return them as `Static` numbers.
For example, if `A isa Base.Matrix`, `offsets(A) === (StaticInt(1), StaticInt(1))`.
"""
@inline offsets(x, i) = static_first(indices(x, i))
# Explicit tuple needed for inference.
offsets(x) = eachop(offsets, x, nstatic(Val(ndims(x))))
offsets(::Tuple) = (One(),)

"""
contiguous_axis(::Type{T}) -> StaticInt{N}

Returns the axis of an array of type `T` containing contiguous data.
If no axis is contiguous, it returns `StaticInt{-1}`.
If unknown, it returns `nothing`.
"""
contiguous_axis(x) = contiguous_axis(typeof(x))
function contiguous_axis(::Type{T}) where {T}
    if parent_type(T) <: T
        return nothing
    else
        return contiguous_axis(parent_type(T))
    end
end
contiguous_axis(::Type{<:Array}) = StaticInt{1}()
contiguous_axis(::Type{<:Tuple}) = StaticInt{1}()
function contiguous_axis(::Type{T}) where {T<:VecAdjTrans}
    c = contiguous_axis(parent_type(T))
    if c === nothing
        return nothing
    elseif c === One()
        return StaticInt{2}()
    else
        return -One()
    end
end
function contiguous_axis(::Type{T}) where {T<:MatAdjTrans}
    c = contiguous_axis(parent_type(T))
    if c === nothing
        return nothing
    elseif isone(-c)
        return c
    else
        return StaticInt(3) - c
    end
end
function contiguous_axis(::Type{T}) where {I1,I2,T<:PermutedDimsArray{<:Any,<:Any,I1,I2}}
    c = contiguous_axis(parent_type(T))
    if c === nothing
        return nothing
    elseif isone(-c)
        return c
    else
        return StaticInt(I2[c])
    end
end
function contiguous_axis(::Type{T}) where {T<:SubArray}
    return _contiguous_axis(T, contiguous_axis(parent_type(T)))
end

_contiguous_axis(::Type{A}, ::Nothing) where {T,N,P,I,A<:SubArray{T,N,P,I}} = nothing
_contiguous_axis(::Type{A}, c::StaticInt{-1}) where {T,N,P,I,A<:SubArray{T,N,P,I}} = c
function _contiguous_axis(::Type{A}, c::StaticInt{C}) where {T,N,P,I,A<:SubArray{T,N,P,I},C}
    if _get_tuple(I, c) <: AbstractUnitRange
        return from_parent_dims(A)[C]
    elseif _get_tuple(I, c) <: AbstractArray
        return -One()
    elseif _get_tuple(I, c) <: Integer
        return -One()
    else
        return nothing
    end
end

# contiguous_if_one(::StaticInt{1}) = StaticInt{1}()
# contiguous_if_one(::Any) = StaticInt{-1}()
function contiguous_axis(::Type{R}) where {T,N,S,A<:Array{S},R<:ReinterpretArray{T,N,S,A}}
    if isbitstype(S)
        return One()
    else
        return nothing
    end
end

"""
    contiguous_axis_indicator(::Type{T}) -> Tuple{Vararg{StaticBool}}

Returns a tuple boolean `Val`s indicating whether that axis is contiguous.
"""
function contiguous_axis_indicator(::Type{A}) where {D,A<:AbstractArray{<:Any,D}}
    return contiguous_axis_indicator(contiguous_axis(A), Val(D))
end
contiguous_axis_indicator(::A) where {A<:AbstractArray} = contiguous_axis_indicator(A)
contiguous_axis_indicator(::Nothing, ::Val) = nothing
function contiguous_axis_indicator(c::StaticInt{N}, dim::Val{D}) where {N,D}
    return map(i -> eq(c, i), nstatic(dim))
end

function rank_to_sortperm(R::Tuple{Vararg{StaticInt,N}}) where {N}
    sp = ntuple(zero, Val{N}())
    r = ntuple(n -> sum(R[n] .≥ R), Val{N}())
    @inbounds for n = 1:N
        sp = Base.setindex(sp, n, r[n])
    end
    return sp
end

stride_rank(x) = stride_rank(typeof(x))
function stride_rank(::Type{T}) where {T}
    if parent_type(T) <: T
        return nothing
    else
        return stride_rank(parent_type(T))
    end
end
stride_rank(::Type{Array{T,N}}) where {T,N} = nstatic(Val(N))
stride_rank(::Type{<:Tuple}) = (One(),)

stride_rank(::Type{T}) where {T<:VecAdjTrans} = (StaticInt(2), StaticInt(1))
stride_rank(::Type{T}) where {T<:MatAdjTrans} = _stride_rank(T, stride_rank(parent_type(T)))
_stride_rank(::Type{T}, ::Nothing) where {T<:MatAdjTrans} = nothing
function _stride_rank(::Type{T}, rank) where {T<:MatAdjTrans}
    return (getfield(rank, 2), getfield(rank, 1))
end

function stride_rank(::Type{T},) where {T<:PermutedDimsArray}
    return _stride_rank(T, stride_rank(parent_type(T)))
end
_stride_rank(::Type{T}, ::Nothing) where {T<:PermutedDimsArray} = nothing
_stride_rank(::Type{T}, r) where {T<:PermutedDimsArray} = permute(r, to_parent_dims(T))

stride_rank(::Type{T}) where {T<:SubArray} = _stride_rank(T, stride_rank(parent_type(T)))
_stride_rank(::Any, ::Any) = nothing
_stride_rank(::Type{T}, r::Tuple) where {T<:SubArray} = permute(r, to_parent_dims(T))

stride_rank(x, i) = stride_rank(x)[i]
function stride_rank(::Type{R}) where {T,N,S,A<:Array{S},R<:Base.ReinterpretArray{T,N,S,A}}
    return nstatic(Val(N))
end

function stride_rank(::Type{Base.ReshapedArray{T, N, P, Tuple{Vararg{Base.SignedMultiplicativeInverse{Int},M}}}}) where {T,N,P,M}
    _reshaped_striderank(is_column_major(P), Val{N}(), Val{M}())
end
_reshaped_striderank(::True, ::Val{N}, ::Val{0}) where {N} = nstatic(Val(N))
_reshaped_striderank(_, __, ___) = nothing

"""
    contiguous_batch_size(::Type{T}) -> StaticInt{N}

Returns the Base.size of contiguous batches if `!isone(stride_rank(T, contiguous_axis(T)))`.
If `isone(stride_rank(T, contiguous_axis(T)))`, then it will return `StaticInt{0}()`.
If `contiguous_axis(T) == -1`, it will return `StaticInt{-1}()`.
If unknown, it will return `nothing`.
"""
contiguous_batch_size(x) = contiguous_batch_size(typeof(x))
contiguous_batch_size(::Type{T}) where {T} = _contiguous_batch_size(contiguous_axis(T), stride_rank(T))
_contiguous_batch_size(_, __) = nothing
function _contiguous_batch_size(::StaticInt{D}, ::R) where {D,R<:Tuple}
    if R.parameters[D].parameters[1] === 1
        return Zero()
    else
        return nothing
    end
end

contiguous_batch_size(::Type{Array{T,N}}) where {T,N} = StaticInt{0}()
contiguous_batch_size(::Type{<:Tuple}) = StaticInt{0}()
function contiguous_batch_size(::Type{T}) where {T<:Union{Transpose,Adjoint}}
    return contiguous_batch_size(parent_type(T))
end
function contiguous_batch_size(::Type{T}) where {T<:PermutedDimsArray}
    return contiguous_batch_size(parent_type(T))
end
function contiguous_batch_size(::Type{S}) where {N,NP,T,A<:AbstractArray{T,NP},I,S<:SubArray{T,N,A,I}}
    return _contiguous_batch_size(S, contiguous_batch_size(A), contiguous_axis(A))
end
_contiguous_batch_size(::Any, ::Any, ::Any) = nothing
function _contiguous_batch_size(::Type{<:SubArray{T,N,A,I}}, b::StaticInt{B}, c::StaticInt{C}) where {T,N,A,I,B,C}
    if I.parameters[C] <: AbstractUnitRange
        return b
    else
        return -One()
    end
end
contiguous_batch_size(::Type{<:Base.ReinterpretArray{T,N,S,A}}) where {T,N,S,A} = Zero()

"""
    is_column_major(A) -> True/False

Returns `Val{true}` if elements of `A` are stored in column major order. Otherwise returns `Val{false}`.
"""
is_column_major(A) = is_column_major(stride_rank(A), contiguous_batch_size(A))
is_column_major(sr::Nothing, cbs) = False()
is_column_major(sr::R, cbs) where {R} = _is_column_major(sr, cbs)

# cbs > 0
_is_column_major(sr::R, cbs::StaticInt) where {R} = False()
# cbs <= 0
_is_column_major(sr::R, cbs::Union{StaticInt{0},StaticInt{-1}}) where {R} = is_increasing(sr)

"""
    dense_dims(::Type{T}) -> NTuple{N,Bool}

Returns a tuple of indicators for whether each axis is dense.
An axis `i` of array `A` is dense if `stride(A, i) * Base.size(A, i) == stride(A, j)` where `stride_rank(A)[i] + 1 == stride_rank(A)[j]`.
"""
dense_dims(x) = dense_dims(typeof(x))
function dense_dims(::Type{T}) where {T}
    if parent_type(T) <: T
        return nothing
    else
        return dense_dims(parent_type(T))
    end
end
_all_dense(::Val{N}) where {N} = ntuple(_ -> True(), Val{N}())

dense_dims(::Type{Array{T,N}}) where {T,N} = _all_dense(Val{N}())
dense_dims(::Type{<:Tuple}) = (True(),)
function dense_dims(::Type{T}) where {T<:VecAdjTrans}
    dense = dense_dims(parent_type(T))
    if dense === nothing
        return nothing
    else
        return (True(), first(dense))
    end
end
function dense_dims(::Type{T}) where {T<:MatAdjTrans}
    dense = dense_dims(parent_type(T))
    if dense === nothing
        return nothing
    else
        return (last(dense), first(dense))
    end
end
function dense_dims(::Type{T}) where {T<:PermutedDimsArray}
    dense = dense_dims(parent_type(T))
    if dense === nothing
        return nothing
    else
        return permute(dense, to_parent_dims(T))
    end
end
function dense_dims(::Type{S}) where {N,NP,T,A<:AbstractArray{T,NP},I,S<:SubArray{T,N,A,I}}
    return _dense_dims(S, dense_dims(A), Val(stride_rank(A)))
end

_dense_dims(::Any, ::Any) = nothing
@generated function _dense_dims(
    ::Type{S},
    ::D,
    ::Val{R},
) where {D,R,N,NP,T,A<:AbstractArray{T,NP},I,S<:SubArray{T,N,A,I}}
    still_dense = true
    sp = rank_to_sortperm(R)
    densev = Vector{Bool}(undef, NP)
    for np = 1:NP
        spₙ = sp[np]
        if still_dense
            still_dense = D.parameters[spₙ] <: True
        end
        densev[spₙ] = still_dense
        # a dim not being complete makes later dims not dense
        still_dense &= (I.parameters[spₙ] <: Base.Slice)::Bool
    end
    dense_tup = Expr(:tuple)
    for np = 1:NP
        Iₙₚ = I.parameters[np]
        if Iₙₚ <: AbstractUnitRange
            if densev[np]
                push!(dense_tup.args, :(True()))
            else
                push!(dense_tup.args, :(False()))
            end
        elseif Iₙₚ <: AbstractVector
            push!(dense_tup.args, :(False()))
        end
    end
    # If n != N, then an axis was indexed by something other than an integer or `AbstractUnitRange`, so we return `nothing`.
    if length(dense_tup.args) === N
        return dense_tup
    else
        return nothing
    end
end

function dense_dims(::Type{Base.ReshapedArray{T, N, P, Tuple{Vararg{Base.SignedMultiplicativeInverse{Int},M}}}}) where {T,N,P,M}
    return _reshaped_dense_dims(dense_dims(P), is_column_major(P), Val{N}(), Val{M}())
end
_reshaped_dense_dims(_, __, ___, ____) = nothing
function _reshaped_dense_dims(dense::D, ::True, ::Val{N}, ::Val{0}) where {D,N}
    if all(dense)
        return _all_dense(Val{N}())
    else
        return nothing
    end
end

"""
    known_offsets(::Type{T}[, d]) -> Tuple

Returns a tuple of offset values known at compile time. If the offset of a given axis is
not known at compile time `nothing` is returned its position.
"""
@inline known_offsets(x, d) = known_offsets(x)[to_dims(x, d)]
known_offsets(x) = known_offsets(typeof(x))
@generated function known_offsets(::Type{T}) where {T}
    out = Expr(:tuple)
    for p in axes_types(T).parameters
        push!(out.args, known_first(p))
    end
    return out
end

"""
    known_strides(::Type{T}[, d]) -> Tuple

Returns the strides of array `A` known at compile time. Any strides that are not known at
compile time are represented by `nothing`.
"""
known_strides(x) = known_strides(typeof(x))
known_strides(x, d) = known_strides(x)[to_dims(x, d)]
known_strides(::Type{T}) where {T<:Vector} = (1,)
function known_strides(::Type{T}) where {T<:MatAdjTrans}
    return permute(known_strides(parent_type(T)), to_parent_dims(T))
end
@inline function known_strides(::Type{T}) where {T<:VecAdjTrans}
    strd = first(known_strides(parent_type(T)))
    return (strd, strd)
end
@inline function known_strides(::Type{T}) where {I1,T<:PermutedDimsArray{<:Any,<:Any,I1}}
    return permute(known_strides(parent_type(T)), Val{I1}())
end
@inline function known_strides(::Type{T}) where {I1,T<:SubArray{<:Any,<:Any,<:Any,I1}}
    return permute(known_strides(parent_type(T)), to_parent_dims(T))
end
function known_strides(::Type{T}) where {T}
    if ndims(T) === 1
        return (1,)
    else
        return size_to_strides(known_size(T), 1)
    end
end

"""
    strides(A) -> Tuple

Returns the strides of array `A`. If any strides are known at compile time,
these should be returned as `Static` numbers. For example:
```julia
julia> A = rand(3,4);

julia> ArrayInterface.strides(A)
(static(1), 3)

Additionally, the behavior differs from `Base.strides` for adjoint vectors:

julia> x = rand(5);

julia> ArrayInterface.strides(x')
(static(1), static(1))

This is to support the pattern of using just the first stride for linear indexing, `x[i]`,
while still producing correct behavior when using valid cartesian indices, such as `x[1,i]`.
```
"""
@inline strides(A::Vector{<:Any}) = (StaticInt(1),)
@inline strides(A::Array{<:Any,N}) where {N} = (StaticInt(1), Base.tail(Base.strides(A))...)
function strides(x)
    defines_strides(x) || _stride_error(x)
    return size_to_strides(size(x), One())
end
#@inline strides(A) = _strides(A, Base.strides(A), contiguous_axis(A))

strides(a, dim) = strides(a, to_dims(a, dim))
function strides(a::A, dim::Integer) where {A}
    if parent_type(A) <: A
        return Base.stride(a, Int(dim))
    else
        return strides(parent(a), to_parent_dims(A, dim))
    end
end

_stride_error(@nospecialize(x)) = throw(MethodError(ArrayInterface.strides, (x,)))

function strides(x::VecAdjTrans)
    st = first(strides(parent(x)))
    return (st, st)
end
@inline strides(B::MatAdjTrans) = permute(strides(parent(B)), to_parent_dims(B))
@inline strides(B::PermutedDimsArray) = permute(strides(parent(B)), to_parent_dims(B))

@inline stride(A::AbstractArray, ::StaticInt{N}) where {N} = strides(A)[N]
@inline stride(A::AbstractArray, ::Val{N}) where {N} = strides(A)[N]
stride(A, i) = Base.stride(A, i) # for type stability

getmul(x::Tuple, y::Tuple, ::StaticInt{i}) where {i} = getfield(x, i) * getfield(y, i)
function strides(A::SubArray)
    return eachop(getmul, map(maybe_static_step, A.indices), strides(parent(A)), to_parent_dims(A))
end

maybe_static_step(x::AbstractRange) = static_step(x)
maybe_static_step(_) = nothing

@generated function size_to_strides(sz::S, init) where {N,S<:Tuple{Vararg{Any,N}}}
    out = Expr(:block, Expr(:meta, :inline))
    t = Expr(:tuple, :init)
    prev = :init
    i = 1
    while i <= (N - 1)
        if S.parameters[i] <: Nothing || (i > 1 &&  t.args[i - 1] === :nothing)
            push!(t.args, :nothing)
        else
            next = Symbol(:val_, i)
            push!(out.args, :($next = $prev * getfield(sz, $i)))
            push!(t.args, next)
            prev = next
        end
        i += 1
    end
    push!(out.args, t)
    return out
end

