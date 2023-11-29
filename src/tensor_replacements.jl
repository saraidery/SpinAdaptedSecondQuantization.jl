export look_for_tensor_replacements, make_exchange_transformer,
    look_for_tensor_replacements_smart

function do_tensor_replacement(t::Term, transformer)
    old_tensors = t.tensors

    new_terms = Term[]
    other_terms = Term[]

    for (i, tens) in enumerate(old_tensors)
        result = transformer(tens)

        if !isnothing(result)
            new_scal, new_tens, other_scal, other_tens = result

            new_tensors = copy(old_tensors)
            new_tensors[i] = new_tens

            new_term = Term(
                t.scalar * new_scal,
                t.sum_indices,
                t.deltas,
                new_tensors,
                t.operators,
                t.constraints
            )

            other_tensors = copy(old_tensors)
            other_tensors[i] = other_tens

            other_term = Term(
                t.scalar * other_scal,
                t.sum_indices,
                t.deltas,
                other_tensors,
                t.operators,
                t.constraints
            )

            push!(new_terms, new_term)
            push!(other_terms, other_term)
        end
    end

    new_terms, other_terms
end

function make_exchange_transformer(from, to)
    function g2L_transformer(t::T) where {T<:Tensor}
        if length(get_indices(t)) != 4 || get_symbol(t) != from
            return
        end

        -1 // 2, reorder_indices(t, [1, 4, 3, 2]), 1 // 2, T(to, get_indices(t))
    end

    g2L_transformer
end

function look_for_tensor_replacements(ex::Expression, transformer)
    is_done = false

    while !is_done
        is_done = true

        for i in eachindex(ex.terms)
            replacements, other_replacements =
                do_tensor_replacement(ex[i], transformer)

            for (replacement, other_replacement) in
                zip(replacements, other_replacements)
                for j in eachindex(ex.terms)
                    if i != j
                        if possibly_equal(ex[j], replacement)
                            simple_replacement = simplify_heavy(replacement)
                            if ex[j] == simple_replacement
                                is_done = false

                                new_terms = copy(ex.terms)
                                new_terms[i] = simplify_heavy(other_replacement)
                                deleteat!(new_terms, j)
                                ex = Expression(new_terms)
                            end
                        end
                    end
                    if !is_done
                        break
                    end
                end
                if !is_done
                    break
                end
            end
            if !is_done
                break
            end
        end
    end

    ex
end

function look_for_tensor_replacements_smart(ex::Expression, transformer)
    if iszero(ex)
        return ex
    end

    nth = Threads.nthreads()

    new_things_th = [Pair{NTuple{2,Int},Term}[] for _ in 1:nth]

    Threads.@threads for th_id in 1:nth
        for i in th_id:nth:length(ex.terms)
            replacements, other_replacements =
                do_tensor_replacement(ex[i], transformer)

            for (replacement, other_replacement) in
                zip(replacements, other_replacements)
                for j in eachindex(ex.terms)
                    if i != j && possibly_equal(ex[j], replacement)
                        simple_replacement = simplify_heavy(replacement)
                        if ex[j] == simple_replacement
                            push!(new_things_th[th_id],
                                (i, j) => simplify_heavy(other_replacement))
                        end
                    end
                end
            end
        end
    end

    new_things, rest = Iterators.peel(new_things_th)

    for new_things2 in rest
        append!(new_things, new_things2)
    end

    actually_removing = Int[]
    new_terms = Term[]

    for ((i, j), t) in new_things
        if i ∉ actually_removing && j ∉ actually_removing
            push!(actually_removing, i)
            push!(actually_removing, j)

            push!(new_terms, t)
        end
    end

    extra_expression = look_for_tensor_replacements_smart(
        Expression(new_terms), transformer
    )

    old_terms = Expression(
        [t for (i, t) in enumerate(ex.terms) if i ∉ actually_removing]
    )

    old_terms + extra_expression
end
