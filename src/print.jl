#  Copyright 2017, Iain Dunning, Joey Huchette, Miles Lubin, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.
#############################################################################
# JuMP
# An algebraic modeling language for Julia
# See https://github.com/jump-dev/JuMP.jl
#############################################################################

Base.show(io::IO, model::AbstractModel) = _print_summary(io, model)

struct _LatexModel{T<:AbstractModel}
    model::T
end

"""
    latex_formulation(model::AbstractModel)

Wrap `model` in a type so that it can be pretty-printed as `text/latex` in a
notebook like IJulia, or in Documenter.

To render the model, end the cell with `latex_formulation(model)`, or call
`display(latex_formulation(model))` in to force the display of the model from
inside a function.
"""
latex_formulation(model::AbstractModel) = _LatexModel(model)

Base.show(io::IO, model::_LatexModel) = _print_latex(io, model.model)

Base.show(io::IO, ::MIME"text/latex", model::_LatexModel) = show(io, model)

function Base.print(model::AbstractModel)
    for d in Base.Multimedia.displays
        if Base.Multimedia.displayable(d, "text/latex") &&
           startswith("$(typeof(d))", "IJulia.")
            return display(d, "text/latex", latex_formulation(model))
        end
    end
    return _print_model(stdout, model)
end

Base.print(io::IO, model::AbstractModel) = _print_model(io, model)

# Whether something is zero or not for the purposes of printing it
# oneunit is useful e.g. if coef is a Unitful quantity.
_is_zero_for_printing(coef) = abs(coef) < 1e-10 * oneunit(coef)

# Whether something is one or not for the purposes of printing it.
_is_one_for_printing(coef) = _is_zero_for_printing(abs(coef) - oneunit(coef))

# Helper function that rounds carefully for the purposes of printing
# e.g.   5.3  =>  5.3
#        1.0  =>  1
function _string_round(x::Float64)
    if isinteger(x)
        return string(round(Int, x))
    end
    return string(x)
end

_string_round(x) = string(x)

# REPL-specific symbols
# Anything here: https://en.wikipedia.org/wiki/Windows-1252
# should probably work fine on Windows
function _math_symbol(::MIME"text/plain", name::Symbol)
    if name == :leq
        return Sys.iswindows() ? "<=" : "≤"
    elseif name == :geq
        return Sys.iswindows() ? ">=" : "≥"
    elseif name == :eq
        return Sys.iswindows() ? "==" : "="
    elseif name == :sq
        return "²"
    else
        @assert name == :in
        return Sys.iswindows() ? "in" : "∈"
    end
end

# IJulia-specific symbols.
function _math_symbol(::MIME"text/latex", name::Symbol)
    if name == :leq
        return "\\leq"
    elseif name == :geq
        return "\\geq"
    elseif name == :eq
        return "="
    elseif name == :sq
        return "^2"
    else
        @assert name == :in
        return "\\in"
    end
end

_wrap_in_math_mode(str) = "\$\$ $str \$\$"
_wrap_in_inline_math_mode(str) = "\$ $str \$"

_plural(n) = isone(n) ? "" : "s"

#------------------------------------------------------------------------
## Model
#------------------------------------------------------------------------

"""
    name(model::AbstractModel)

Return the [`MOI.Name`](@ref) attribute of `model`'s [`backend`](@ref), or a
default if empty.
"""
name(model::AbstractModel) = "An Abstract JuMP Model"

function name(model::Model)
    ret = MOI.get(model, MOI.Name())
    return isempty(ret) ? "A JuMP Model" : ret
end

"""
    _print_summary(io::IO, model::AbstractModel)

Print a plain-text summary of `model` to `io`.

For this method to work, an `AbstractModel` subtype should implement:
 * `name(::AbstractModel)`
 * `show_objective_function_summary`
 * `show_constraints_summary`
 * `show_backend_summary`
"""
function _print_summary(io::IO, model::AbstractModel)
    println(io, name(model))
    sense = objective_sense(model)
    if sense == MAX_SENSE
        println(io, "Maximization problem with:")
    elseif sense == MIN_SENSE
        println(io, "Minimization problem with:")
    else
        println(io, "Feasibility problem with:")
    end
    n = num_variables(model)
    println(io, "Variable", _plural(n), ": ", n)
    if sense != FEASIBILITY_SENSE
        show_objective_function_summary(io, model)
    end
    show_constraints_summary(io, model)
    show_backend_summary(io, model)
    if !isempty(object_dictionary(model))
        print(io, "\nNames registered in the model: ")
        print(io, join(sort!(collect(keys(object_dictionary(model)))), ", "))
    end
    return
end

"""
    show_objective_function_summary(io::IO, model::AbstractModel)

Write to `io` a summary of the objective function type.
"""
function show_objective_function_summary(io::IO, model::Model)
    nlobj = _nlp_objective_function(model)
    print(io, "Objective function type: ")
    if nlobj === nothing
        println(io, objective_function_type(model))
    else
        println(io, "Nonlinear")
    end
    return
end

"""
    show_constraints_summary(io::IO, model::AbstractModel)

Write to `io` a summary of the number of constraints.
"""
function show_constraints_summary(io::IO, model::Model)
    for (F, S) in list_of_constraint_types(model)
        n = num_constraints(model, F, S)
        println(io, "`$F`-in-`$S`: $n constraint", _plural(n))
    end
    n = num_nonlinear_constraints(model)
    if n > 0
        println(io, "Nonlinear: ", n, " constraint", _plural(n))
    end
    return
end

"""
    show_backend_summary(io::IO, model::Model)

Print a summary of the optimizer backing `model`.

`AbstractModel`s should implement this method.
"""
function show_backend_summary(io::IO, model::Model)
    model_mode = mode(model)
    println(io, "Model mode: ", model_mode)
    if model_mode == MANUAL || model_mode == AUTOMATIC
        println(io, "CachingOptimizer state: ", MOIU.state(backend(model)))
    end
    # The last print shouldn't have a new line
    print(io, "Solver name: ", solver_name(model))
    return
end

"""
    _print_model(io::IO, model::AbstractModel)

Print a plain-text formulation of `model` to `io`.

For this method to work, an `AbstractModel` subtype must implement:
 * `objective_function_string`
 * `constraints_string`
 * `_nl_subexpression_string`
"""
function _print_model(io::IO, model::AbstractModel)
    mode = MIME("text/plain")
    sense = objective_sense(model)
    if sense == MAX_SENSE
        println(io, "Max ", objective_function_string(mode, model))
    elseif sense == MIN_SENSE
        println(io, "Min ", objective_function_string(mode, model))
    else
        println(io, "Feasibility")
    end
    println(io, "Subject to")
    for constraint in constraints_string(mode, model)
        println(io, " ", replace(constraint, '\n' => "\n "))
    end
    nl_subexpressions = _nl_subexpression_string(mode, model)
    if !isempty(nl_subexpressions)
        println(io, "With NL expressions")
        for expr in nl_subexpressions
            println(io, " ", expr)
        end
    end
    return
end

"""
    _print_latex(io::IO, model::AbstractModel)

Print a LaTeX formulation of `model` to `io`.

For this method to work, an `AbstractModel` subtype must implement:
 * `objective_function_string`
 * `constraints_string`
 * `_nl_subexpression_string`
"""
function _print_latex(io::IO, model::AbstractModel)
    mode = MIME("text/latex")
    println(io, "\$\$ \\begin{aligned}")
    sense = objective_sense(model)
    if sense == MAX_SENSE
        print(io, "\\max\\quad & ")
        println(io, objective_function_string(mode, model), "\\\\")
    elseif sense == MIN_SENSE
        print(io, "\\min\\quad & ")
        println(io, objective_function_string(mode, model), "\\\\")
    else
        println(io, "\\text{feasibility}\\\\")
    end
    constraints = constraints_string(mode, model)
    if !isempty(constraints)
        print(io, "\\text{Subject to} \\quad")
        for constraint in constraints
            println(io, " & ", constraint, "\\\\")
        end
    end
    nl_subexpressions = _nl_subexpression_string(mode, model)
    if !isempty(nl_subexpressions)
        print(io, "\\text{With NL expressions} \\quad")
        for expr in nl_subexpressions
            println(io, " & ", expr, "\\\\")
        end
    end
    print(io, "\\end{aligned} \$\$")
    return
end

"""
    model_string(mode::MIME, model::AbstractModel)

Return a `String` representation of `model` given the `mode`.
"""
function model_string(mode::MIME, model::AbstractModel)
    if mode == MIME("text/latex")
        return sprint(_print_latex, model)
    end
    return sprint(_print_model, model)
end

"""
    objective_function_string(mode, model::AbstractModel)::String

Return a `String` describing the objective function of the model.
"""
function objective_function_string(mode, model::Model)
    nlobj = _nlp_objective_function(model)
    if nlobj === nothing
        return function_string(mode, objective_function(model))
    end
    return nl_expr_string(model, mode, nlobj)
end

"""
    nl_constraint_string(model::Model, mode::MIME, c::_NonlinearConstraint)

Return a string representation of the nonlinear constraint `c` belonging to
`model`, given the `mode`.
"""
function nl_constraint_string(model::Model, mode::MIME, c::_NonlinearConstraint)
    s = _sense(c)
    nl = nl_expr_string(model, mode, c.terms)
    if s == :range
        return string(
            _string_round(c.lb),
            " ",
            _math_symbol(mode, :leq),
            " ",
            nl,
            " ",
            _math_symbol(mode, :leq),
            " ",
            _string_round(c.ub),
        )
    end
    if s == :<=
        rel = _math_symbol(mode, :leq)
    elseif s == :>=
        rel = _math_symbol(mode, :geq)
    else
        rel = _math_symbol(mode, :eq)
    end
    return string(nl, " ", rel, " ", _string_round(_rhs(c)))
end

"""
    constraints_string(mode, model::AbstractModel)::Vector{String}

Return a list of `String`s describing each constraint of the model.
"""
function constraints_string(mode, model::Model)
    strings = String[
        constraint_string(mode, cref; in_math_mode = true) for
        (F, S) in list_of_constraint_types(model) for
        cref in all_constraints(model, F, S)
    ]
    if model.nlp_data !== nothing
        for c in model.nlp_data.nlconstr
            push!(strings, nl_constraint_string(model, mode, c))
        end
    end
    return strings
end

"""
    nl_expr_string(model::Model, mode::MIME, c::_NonlinearExprData)

Return a string representation of the nonlinear expression `c` belonging to
`model`, given the `mode`.
"""
function nl_expr_string(model::Model, mode::MIME, c::_NonlinearExprData)
    ex = _tape_to_expr(
        model,
        1,
        c.nd,
        adjmat(c.nd),
        c.const_values,
        [],
        [],
        model.nlp_data.user_operators,
        false,
        false,
        mode,
    )
    return string(_latexify_exponentials(mode, ex))
end

# Change x ^ -2.0 to x ^ {-2.0}
# x ^ (x ^ 2.0) to x ^ {x ^ {2.0}}
# and so on
_latexify_exponentials(::MIME, ex) = ex

function _latexify_exponentials(mode::MIME"text/latex", ex::Expr)
    for i in 1:length(ex.args)
        ex.args[i] = _latexify_exponentials(mode, ex.args[i])
    end
    if length(ex.args) == 3 && ex.args[1] == :^
        ex.args[3] = Expr(:braces, ex.args[3])
    end
    return ex
end

_nl_subexpression_string(::Any, ::AbstractModel) = String[]

function _nl_subexpression_string(mode::MIME, model::Model)
    if model.nlp_data === nothing
        return String[]
    end
    strings = String[]
    for k in 1:length(model.nlp_data.nlexpr)::Int
        expr = nl_expr_string(model, mode, model.nlp_data.nlexpr[k])
        if mode == MIME("text/latex")
            push!(strings, "subexpression_{$k}: $expr")
        else
            push!(strings, "subexpression[$k]: $expr")
        end
    end
    return strings
end

anonymous_name(::Any, x::AbstractVariableRef) = "anon"

anonymous_name(::MIME"text/plain", x::VariableRef) = "_[$(index(x).value)]"

function anonymous_name(::MIME"text/latex", x::VariableRef)
    return "{\\_}_{$(index(x).value)}"
end

"""
    function_string(
        mode::MIME,
        func::Union{JuMP.AbstractJuMPScalar,Vector{<:JuMP.AbstractJuMPScalar}},
    )

Return a `String` representing the function `func` using print mode `mode`.
"""
function function_string(mode::MIME"text/plain", v::AbstractVariableRef)
    var_name = name(v)
    if isempty(var_name)
        return anonymous_name(mode, v)
    end
    return var_name
end

function function_string(mode::MIME"text/latex", v::AbstractVariableRef)
    var_name = name(v)
    if isempty(var_name)
        return anonymous_name(mode, v)
    end
    # We need to escape latex math characters that appear in the name.
    # However, it's probably impractical to catch everything, so let's just
    # escape the common ones:
    # Escape underscores to prevent them being treated as subscript markers.
    var_name = replace(var_name, "_" => "\\_")
    # Escape carets to prevent them being treated as superscript markers.
    var_name = replace(var_name, "^" => "\\^")
    # Convert any x[args] to x_{args} so that indices on x print as subscripts.
    m = match(r"^(.*)\[(.+)\]$", var_name)
    if m !== nothing
        var_name = m[1] * "_{" * m[2] * "}"
    end
    return var_name
end

# TODO(odow): remove show_constant in JuMP 1.0
function function_string(mode, a::GenericAffExpr, show_constant = true)
    if length(linear_terms(a)) == 0
        return show_constant ? _string_round(a.constant) : "0"
    end
    terms = fill("", 2 * length(linear_terms(a)))
    for (elm, (coef, var)) in enumerate(linear_terms(a))
        terms[2*elm-1] = coef < zero(coef) ? " - " : " + "
        v = function_string(mode, var)
        if _is_one_for_printing(coef)
            terms[2*elm] = v
        else
            terms[2*elm] = string(_string_round(abs(coef)), " ", v)
        end
    end
    terms[1] = terms[1] == " - " ? "-" : ""
    ret = join(terms)
    if show_constant && !_is_zero_for_printing(a.constant)
        ret = string(
            ret,
            a.constant < zero(a.constant) ? " - " : " + ",
            _string_round(abs(a.constant)),
        )
    end
    return ret
end

function function_string(mode, q::GenericQuadExpr)
    if length(quad_terms(q)) == 0
        return function_string(mode, q.aff)
    end
    terms = fill("", 2 * length(quad_terms(q)))
    for (elm, (coef, var1, var2)) in enumerate(quad_terms(q))
        x = function_string(mode, var1)
        y = function_string(mode, var2)
        terms[2*elm-1] = coef < zero(coef) ? " - " : " + "
        if _is_one_for_printing(coef)
            terms[2*elm] = "$x"
        else
            terms[2*elm] = string(_string_round(abs(coef)), " ", x)
        end
        if x == y
            terms[2*elm] *= _math_symbol(mode, :sq)
        else
            times = mode == MIME("text/latex") ? "\\times " : "*"
            terms[2*elm] *= string(times, y)
        end
    end
    terms[1] = terms[1] == " - " ? "-" : ""
    ret = join(terms)
    aff_str = function_string(mode, q.aff)
    if aff_str == "0"
        return ret
    elseif aff_str[1] == '-'
        return string(ret, " - ", aff_str[2:end])
    else
        return string(ret, " + ", aff_str)
    end
end

function function_string(mode, vector::Vector{<:AbstractJuMPScalar})
    return "[" * join(function_string.(Ref(mode), vector), ", ") * "]"
end

function function_string(
    ::MIME"text/plain",
    A::AbstractMatrix{<:AbstractJuMPScalar},
)
    str = sprint(show, MIME"text/plain"(), A)
    lines = split(str, '\n')
    # We drop the first line with the signature "m×n Array{...}:"
    lines = lines[2:end]
    # We replace the first space by an opening `[`
    lines[1] = '[' * lines[1][2:end]
    for i in 1:length(lines)
        lines[i] = lines[i] * (i == length(lines) ? ']' : ';')
    end
    return join(lines, '\n')
end

function function_string(
    mode::MIME"text/latex",
    A::AbstractMatrix{<:AbstractJuMPScalar},
)
    str = "\\begin{bmatrix}\n"
    for i in 1:size(A, 1)
        line = ""
        for j in 1:size(A, 2)
            if j != 1
                line *= " & "
            end
            if A isa Symmetric && i > j
                line *= "\\cdot"
            else
                line *= function_string(mode, A[i, j])
            end
        end
        str *= line * "\\\\\n"
    end
    return str * "\\end{bmatrix}"
end

function function_string(mode, constraint::AbstractConstraint)
    f = reshape_vector(jump_function(constraint), shape(constraint))
    return function_string(mode, f)
end

function function_string(mode::MIME, p::NonlinearExpression)
    s = nl_expr_string(p.model, mode, p.model.nlp_data.nlexpr[p.index])
    return "subexpression[$(p.index)]: " * s
end

function function_string(::MIME, p::NonlinearParameter)
    for (k, v) in object_dictionary(p.model)
        if v == p
            return "$k == $(value(p))"
        end
    end
    return "parameter[$(p.index)] == $(value(p))"
end

"""
    in_set_string(mode::MIME, set)

Return a `String` representing the membership to the set `set` using print mode
`mode`.
"""
function in_set_string end

function in_set_string(mode::MIME, set::MOI.LessThan)
    return string(_math_symbol(mode, :leq), " ", set.upper)
end

function in_set_string(mode::MIME, set::MOI.GreaterThan)
    return string(_math_symbol(mode, :geq), " ", set.lower)
end

function in_set_string(mode::MIME, set::MOI.EqualTo)
    return string(_math_symbol(mode, :eq), " ", set.value)
end

function in_set_string(::MIME"text/latex", set::MOI.Interval)
    return string("\\in \\[", set.lower, ", ", set.upper, "\\]")
end

function in_set_string(mode::MIME"text/plain", set::MOI.Interval)
    in = _math_symbol(mode, :in)
    return string("$in [", set.lower, ", ", set.upper, "]")
end

in_set_string(::MIME"text/plain", ::MOI.ZeroOne) = "binary"
in_set_string(::MIME"text/latex", ::MOI.ZeroOne) = "\\in \\{0, 1\\}"

in_set_string(::MIME"text/plain", ::MOI.Integer) = "integer"
in_set_string(::MIME"text/latex", ::MOI.Integer) = "\\in \\mathbb{Z}"

function in_set_string(mode, set::Union{PSDCone,MOI.AbstractSet})
    # Use an `if` here instead of multiple dispatch to avoid ambiguity errors.
    if mode == MIME("text/plain")
        return _math_symbol(mode, :in) * " $(set)"
    else
        @assert mode == MIME("text/latex")
        set_str = replace(replace(string(set), "{" => "\\{"), "}" => "\\}")
        return "\\in \\text{$(set_str)}"
    end
end

"""
    in_set_string(mode::MIME, constraint::AbstractConstraint)

Return a `String` representing the membership to the set of the constraint
`constraint` using print mode `mode`.
"""
function in_set_string(mode, constraint::AbstractConstraint)
    # Leave `mode` untyped to avoid ambiguities!
    set = reshape_set(moi_set(constraint), shape(constraint))
    return in_set_string(mode, set)
end

"""
    constraint_string(
        mode::MIME,
        ref::ConstraintRef;
        in_math_mode::Bool = false)

Return a string representation of the constraint `ref`, given the `mode`.
"""
function constraint_string(mode::MIME, ref::ConstraintRef; in_math_mode = false)
    return constraint_string(
        mode,
        name(ref),
        constraint_object(ref);
        in_math_mode = in_math_mode,
    )
end

function constraint_string(mode, constraint_object::AbstractConstraint)
    # Leave `mode` untyped to avoid ambiguities!
    func_str = function_string(mode, constraint_object)
    in_set_str = in_set_string(mode, constraint_object)
    if mode == MIME("text/plain")
        lines = split(func_str, '\n')
        lines[1+div(length(lines), 2)] *= " " * in_set_str
        return join(lines, '\n')
    else
        return func_str * " " * in_set_str
    end
end

function constraint_string(
    mode,  # Leave mode untyped to avoid ambiguities
    constraint_name::String,
    constraint_object::AbstractConstraint;
    in_math_mode::Bool = false,
)
    prefix = isempty(constraint_name) ? "" : constraint_name * " : "
    constraint_str = constraint_string(mode, constraint_object)
    if mode == MIME("text/latex")
        if in_math_mode
            return constraint_str
        elseif isempty(prefix)
            return _wrap_in_math_mode(constraint_str)
        else
            return prefix * _wrap_in_inline_math_mode(constraint_str)
        end
    end
    return prefix * constraint_str
end

function Base.show(io::IO, ref::ConstraintRef)
    return print(io, constraint_string(MIME("text/plain"), ref))
end

function Base.show(io::IO, ::MIME"text/latex", ref::ConstraintRef)
    return print(io, constraint_string(MIME("text/latex"), ref))
end

function Base.show(io::IO, f::AbstractJuMPScalar)
    return print(io, function_string(MIME("text/plain"), f))
end

function Base.show(io::IO, ::MIME"text/latex", f::AbstractJuMPScalar)
    return print(io, _wrap_in_math_mode(function_string(MIME("text/latex"), f)))
end

function Base.show(io::IO, evaluator::NLPEvaluator)
    _init_NLP(evaluator.model)
    Base.print(io, "An NLPEvaluator with available features:")
    for feat in MOI.features_available(evaluator)
        print(io, "\n  * :", feat)
    end
    return
end

function Base.show(io::IO, ex::Union{NonlinearExpression,NonlinearParameter})
    return print(io, function_string(MIME("text/plain"), ex))
end

function Base.show(
    io::IO,
    ::MIME"text/latex",
    ex::Union{NonlinearExpression,NonlinearParameter},
)
    return print(io, function_string(MIME("text/latex"), ex))
end

function Base.show(io::IO, c::NonlinearConstraintRef)
    expr = c.model.nlp_data.nlconstr[c.index.value]
    return print(io, nl_constraint_string(c.model, MIME("text/plain"), expr))
end

function Base.show(io::IO, ::MIME"text/latex", c::NonlinearConstraintRef)
    expr = c.model.nlp_data.nlconstr[c.index.value]
    mode = MIME("text/latex")
    s = _wrap_in_math_mode(nl_constraint_string(c.model, mode, expr))
    return print(io, s)
end
