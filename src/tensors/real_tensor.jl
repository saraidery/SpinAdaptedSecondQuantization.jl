export real_tensor

# Simplest type of tensor
struct RealTensor <: Tensor
    symbol::String
    indices::Vector{MOIndex}
end

get_symbol(t::RealTensor) = t.symbol
get_indices(t::RealTensor) = t.indices

real_tensor(symbol, indices...) =
    Expression(RealTensor(symbol, collect(indices)))
