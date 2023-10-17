export optimise_investments

"""
    optimise_investments(graph, params, sets; verbose = false)

Create and solve the model using the `graph` structure, the parameters and sets.
"""
function optimise_investments(graph, params, sets; verbose = false)
    # Sets unpacking
    A = sets.assets
    Ac = sets.assets_consumer
    # Ap = sets.assets_producer
    Ai = sets.assets_investment
    F = edges(graph)
    K = sets.time_steps
    RP = sets.rep_periods

    # Model
    model = Model(HiGHS.Optimizer)
    set_attribute(model, "output_flag", verbose)

    # Variables
    @variable(model, 0 ≤ v_flow[F, RP, K])         #flow from asset a to asset aa [MW]
    @variable(model, 0 ≤ v_investment[Ai], Int)  #number of installed asset units [N]

    # Expressions
    e_investment_cost = @expression(
        model,
        sum(
            params.investment_cost[a] * params.unit_capacity[a] * v_investment[a] for
            a in Ai
        )
    )

    e_variable_cost = @expression(
        model,
        sum(
            params.rep_weight[rp] * params.variable_cost[f.src] * v_flow[f, rp, k] for
            f in F, rp in RP, k in K
        )
    )

    # Objective function
    @objective(model, Min, e_investment_cost + e_variable_cost)

    # Constraints
    # - balance equation
    @constraint(
        model,
        c_balance[a in Ac, rp in RP, k in K],
        sum(v_flow[Edge(alpha, a), rp, k] for alpha in inneighbors(graph, a)) ==
        params.profile[a, rp, k] * params.peak_demand[a]
    )

    # - maximum generation
    @constraint(
        model,
        c_max_prod[f in F, rp in RP, k in K; f.src in Ai],
        v_flow[f, rp, k] <=
        get(params.profile, (f.src, rp, k), 1.0) *
        (params.init_capacity[f.src] + params.unit_capacity[f.src] * v_investment[f.src])
    )

    # print lp file
    write_to_file(model, "model.lp")

    # Solve model
    optimize!(model)

    return (
        objective_value = objective_value(model),
        v_flow = value.(v_flow),
        v_investment = value.(v_investment),
    )
end
