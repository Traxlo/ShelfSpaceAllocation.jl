using Dates, JuMP, Gurobi, Plots, Logging

push!(LOAD_PATH, dirname(@__DIR__))
using ShelfSpaceAllocation

# --- Arguments ---

time_limit = 10 # Seconds
product_path = joinpath(@__DIR__, "data", "Anonymized space allocation data for 9900-shelf.csv")
shelf_path = joinpath(@__DIR__, "data", "scenario_9900_shelves.csv")
output_dir = joinpath(@__DIR__, "output", string(Dates.now()))

# ---

@info "Creating output directory"
mkpath(output_dir)

io = open(joinpath(output_dir, "shelf_space_allocation.log"), "w+")
logger = SimpleLogger(io)
global_logger(logger)

@info "Arguments" time_limit product_path shelf_path output_dir

@info "Loading parameters"
parameters = load_parameters(product_path, shelf_path)
(products, shelves, blocks, modules, P_b, S_m, G_p, H_s, L_p, P_ps, D_p,
    N_p_min, N_p_max, W_p, W_s, M_p, M_s_min, M_s_max, R_p, L_s, H_p, SK_p, SL) = parameters

@info "Creating the model"
model = shelf_space_allocation_model(
    products, shelves, blocks, modules, P_b, S_m, G_p, H_s, L_p, P_ps, D_p,
    N_p_min, N_p_max, W_p, W_s, M_p, M_s_min, M_s_max, R_p, L_s, H_p, SL)

# Try fixing the block width
@info "Starting the optimization"

optimizer = with_optimizer(
    Gurobi.Optimizer,
    TimeLimit=time_limit,
    LogFile=joinpath(output_dir, "gurobi.log"),
    MIPFocus=3,
    # MIPGap=0.01,
    # Presolve=2,
)
optimize!(model, optimizer)

if termination_status(model) == MOI.INFEASIBLE
    exit()
end

@info "Saving the results"
variables = extract_variables(model)
objectives = extract_objectives(parameters, variables)
save_results(parameters, variables, objectives; output_dir=output_dir)

n_ps = variables[:n_ps]
s_p = variables[:s_p]
o_s = variables[:o_s]
b_bs = variables[:b_bs]
x_bs = variables[:x_bs]
z_bs = variables[:z_bs]

@info "Plotting planogram"
p1 = planogram(products, shelves, blocks, P_b, H_s, H_p, W_p, W_s, SK_p, n_ps, o_s, x_bs)
savefig(p1, joinpath(output_dir, "planogram.svg"))

@info "Plotting product facings"
p2 = product_facings(products, shelves, blocks, P_b, N_p_max, n_ps)
savefig(p2, joinpath(output_dir, "product_facings.svg"))

@info "Plotting block allocation"
p3 = block_allocation(shelves, blocks, H_s, W_s, b_bs, x_bs, z_bs)
savefig(p3, joinpath(output_dir, "block_allocation.svg"))

@info "Plotting fill amount"
p4 = fill_amount(shelves, blocks, P_b, n_ps)
savefig(p4, joinpath(output_dir, "fill_amount.svg"))

@info "Plotting fill percentage"
p5 = fill_percentage(
    n_ps, products, shelves, blocks, modules, P_b, S_m, G_p, H_s, L_p, P_ps,
    D_p, N_p_min, N_p_max, W_p, W_s, M_p, M_s_min, M_s_max, R_p, L_s, H_p,
    with_optimizer(Gurobi.Optimizer, TimeLimit=60))
savefig(p5, joinpath(output_dir, "fill_percentage.svg"))

@info "Plotting demand and sales"
p6 = demand_and_sales(blocks, P_b, D_p, s_p)
savefig(p6, joinpath(output_dir, "demand_and_sales.svg"))

close(io)
