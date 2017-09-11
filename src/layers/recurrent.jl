# TODO: broadcasting cat
combine(x, h) = vcat(x, h .* trues(1, size(x, 2)))

# Sequences

struct Seq{T,A<:AbstractVector{T}}
  data::A
end

Seq(xs::AbstractVector{T}) where T = Seq{T,typeof(xs)}(xs)

Seq(xs) = Seq(collect(xs))

Base.getindex(s::Seq, i) = s.data[i]

struct Over{T}
  m::T
end

(m::Over)(xs...) = m.m(xs...)
(m::Over)(xs::Seq) = Seq(map(m, xs.data))

Base.show(io::IO, m::Over) = print(io, "Over(", m.m, ")")

Optimise.children(m::Over) = (m.m,)

# Stateful recurrence

mutable struct Recur{T}
  cell::T
  state
end

Recur(m) = Recur(m, hidden(m))

function (m::Recur)(xs...)
  h, y = m.cell(m.state, xs...)
  m.state = h
  return y
end

(m::Recur)(s::Seq) = Seq(map(m, x.data))

Optimise.children(m::Recur) = (m.cell,)

Base.show(io::IO, m::Recur) = print(io, "Recur(", m.cell, ")")

_truncate(x::AbstractArray) = x
_truncate(x::TrackedArray) = x.data
_truncate(x::Tuple) = _truncate.(x)

truncate!(m) = foreach(truncate!, Optimise.children(m))
truncate!(m::Recur) = (m.state = _truncate(m.state))

# Vanilla RNN

struct RNNCell{D,V}
  d::D
  h::V
end

RNNCell(in::Integer, out::Integer; init = initn) =
  RNNCell(Dense(in+out, out, init = initn), param(initn(out)))

function (m::RNNCell)(h, x)
  h = m.d(combine(x, h))
  return h, h
end

hidden(m::RNNCell) = m.h

Optimise.children(m::RNNCell) = (m.d, m.h)

function Base.show(io::IO, m::RNNCell)
  print(io, "RNNCell(", m.d, ")")
end

RNN(a...; ka...) = Recur(RNNCell(a...; ka...))

# LSTM

struct LSTMCell{D1,D2,V}
  forget::D1
  input::D1
  output::D1
  cell::D2
  h::V; c::V
end

function LSTMCell(in, out; init = initn)
  cell = LSTMCell([Dense(in+out, out, σ, init = initn) for _ = 1:3]...,
                  Dense(in+out, out, tanh, init = initn),
                  param(initn(out)), param(initn(out)))
  cell.forget.b.data .= 1
  return cell
end

function (m::LSTMCell)(h_, x)
  h, c = h_
  x′ = combine(x, h)
  forget, input, output, cell =
    m.forget(x′), m.input(x′), m.output(x′), m.cell(x′)
  c = forget .* c .+ input .* cell
  h = output .* tanh.(c)
  return (h, c), h
end

hidden(m::LSTMCell) = (m.h, m.c)

Optimise.children(m::LSTMCell) =
  (m.forget, m.input, m.output, m.cell, m.h, m.c)

Base.show(io::IO, m::LSTMCell) =
  print(io, "LSTMCell(",
        size(m.forget.W, 2) - size(m.forget.W, 1), ", ",
        size(m.forget.W, 1), ')')

LSTM(a...; ka...) = Recur(LSTMCell(a...; ka...))
