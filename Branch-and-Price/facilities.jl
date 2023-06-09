using CSV, DataFrames, Dates, JuMP, Gurobi
# MASTER NOTE: ONLY NEED TO SPECIFY VARIABLES THAT ARE ALL UPPER CASE + COST_FUNCTION + ODE_EQUATION

# ODE simulation time
TSPAN = (0.0, 7.0)
# Time Length of Interventions
#T = 6
# Total number of plans
TOT_PLANS = 500000

########################### Getting the Threshold on distance ###########################

#Get region data
included_regions_full = ["A","B","C","D","E","F","G","H","I","J"]
regions_to_state_dict = Dict("A" => ["Connecticut", "Maine", "Massachusetts", "New Hampshire", "Rhode Island", "Vermont", "New York"],
                            "B" => ["Delaware", "District of Columbia", "Maryland", "Pennsylvania", "Virginia", "West Virginia", "New Jersey"],
                            "C" => ["North Carolina", "South Carolina", "Georgia", "Florida"],
                            "D" => ["Kentucky", "Tennessee", "Alabama", "Mississippi"],
                            "E" => ["Illinois", "Indiana", "Michigan", "Minnesota", "Ohio", "Wisconsin"],
                            "F" => ["Arkansas", "Louisiana", "New Mexico", "Oklahoma", "Texas"],
                            "G" => ["Iowa", "Kansas", "Missouri", "Nebraska"],
                            "H" => ["Colorado", "Montana", "North Dakota", "South Dakota", "Utah", "Wyoming"],
                            "I" => ["Arizona", "California", "Hawaii", "Nevada"],
                            "J" => ["Alaska", "Idaho", "Oregon", "Washington"])

regions = [a for x in included_regions_full for a in regions_to_state_dict[x]]
global N_REGION = sum([length(regions_to_state_dict[x]) for x in included_regions_full])
regions_mapping_dict = Dict(zip(collect(1:N_REGION), regions))
num_mapping_dict = Dict(value => key for (key, value) in regions_mapping_dict)
# Region Weights
WEIGHT = [1.00 for i in  1:N_REGION]

#Get the group of each state
state_to_group = Dict()
for state in regions
    for group in collect(keys(regions_to_state_dict))
        if state in regions_to_state_dict[group]
            state_to_group[state] = group
        end
    end
end 

#Get the Traveling distance between the centers and the states
data_dist = CSV.read("data/vaccine/distances.csv", DataFrame, header = true)
names_centers = [names(data_dist)[i] for i in 2:475]
FACILITY_LOCATIONS = length(names_centers)
state_abbreviations = Dict("Alabama" => "AL", "Alaska" => "AK", "Arizona" => "AZ", "Arkansas" => "AR", "California" => "CA", "Colorado" => "CO", "Connecticut" => "CT", "District of Columbia" => "DC" ,"Delaware" => "DE", "Florida" => "FL", "Georgia" => "GA", "Hawaii" => "HI", "Idaho" => "ID", "Illinois" => "IL", "Indiana" => "IN", "Iowa" => "IA", "Kansas" => "KS", "Kentucky" => "KY", "Louisiana" => "LA", "Maine" => "ME", "Maryland" => "MD", "Massachusetts" => "MA", "Michigan" => "MI", "Minnesota" => "MN", "Mississippi" => "MS", "Missouri" => "MO", "Montana" => "MT", "Nebraska" => "NE", "Nevada" => "NV", "New Hampshire" => "NH", "New Jersey" => "NJ", "New Mexico" => "NM", "New York" => "NY", "North Carolina" => "NC", "North Dakota" => "ND", "Ohio" => "OH", "Oklahoma" => "OK", "Oregon" => "OR", "Pennsylvania" => "PA", "Rhode Island" => "RI", "South Carolina" => "SC", "South Dakota" => "SD", "Tennessee" => "TN", "Texas" => "TX", "Utah" => "UT", "Vermont" => "VT", "Virginia" => "VA", "Washington" => "WA", "West Virginia" => "WV", "Wisconsin" => "WI", "Wyoming" => "WY")
us_states = Dict("AL"=>"Alabama","AK"=>"Alaska","AZ"=>"Arizona","AR"=>"Arkansas","CA"=>"California","CO"=>"Colorado","CT"=>"Connecticut", "DC" => "District of Columbia", "DE"=>"Delaware","FL"=>"Florida","GA"=>"Georgia","HI"=>"Hawaii","ID"=>"Idaho","IL"=>"Illinois","IN"=>"Indiana","IA"=>"Iowa","KS"=>"Kansas","KY"=>"Kentucky","LA"=>"Louisiana","ME"=>"Maine","MD"=>"Maryland","MA"=>"Massachusetts","MI"=>"Michigan","MN"=>"Minnesota","MS"=>"Mississippi","MO"=>"Missouri","MT"=>"Montana","NE"=>"Nebraska","NV"=>"Nevada","NH"=>"New Hampshire","NJ"=>"New Jersey","NM"=>"New Mexico","NY"=>"New York","NC"=>"North Carolina","ND"=>"North Dakota","OH"=>"Ohio","OK"=>"Oklahoma","OR"=>"Oregon","PA"=>"Pennsylvania","RI"=>"Rhode Island","SC"=>"South Carolina","SD"=>"South Dakota","TN"=>"Tennessee","TX"=>"Texas","UT"=>"Utah","VT"=>"Vermont","VA"=>"Virginia","WA"=>"Washington","WV"=>"West Virginia","WI"=>"Wisconsin","WY"=>"Wyoming")
COST_DIST = [[filter(row -> row.Column1 == state_abbreviations[regions_mapping_dict[i]], data_dist)[1, names_centers[j]] for j in 1:FACILITY_LOCATIONS] for i in 1:N_REGION]
dist_facilities = CSV.read("data/vaccine/distances_facilities.csv", DataFrame, header = true)

#Total number of facilities in the Country
#F_TOT = 30

#Defining threshold and clusters
function find_quantile(arr, quantile)
    n = length(arr)
    idx = round(Int, (n-1)*quantile + 1) # calculate the index of the x-th quantile
    sorted_arr = sort(arr)
    return sorted_arr[idx]
end

function get_travel_threshold(quantile = 0.8)
    TD = Model(Gurobi.Optimizer)
    set_optimizer_attribute(TD, "OutputFlag", 0)

    w = @variable(TD, 0 <= w[1:FACILITY_LOCATIONS] <= 1)
    x = @variable(TD, 0 <= x[1:N_REGION, 1:FACILITY_LOCATIONS])

    @constraint(TD, UNIQUE[i=1:N_REGION], sum(x[i,j] for j in 1:FACILITY_LOCATIONS) == 1)
    @constraint(TD, EXISTS[i=1:N_REGION, j=1:FACILITY_LOCATIONS], x[i,j] <= w[j])
    @constraint(TD, BF, sum(w[j] for j in 1:FACILITY_LOCATIONS) == F_TOT)

    @objective(TD, Min, sum(sum(COST_DIST[i][j]*x[i,j] for j in 1:FACILITY_LOCATIONS) for i in 1:N_REGION))
    optimize!(TD)

    travel_dist_chosen = []
    for i in 1:N_REGION
        for j in 1:FACILITY_LOCATIONS
            if value.(x[i,j]) > 0.00001
                push!(travel_dist_chosen, COST_DIST[i][j])
            end
        end
    end

    thresh = find_quantile(travel_dist_chosen, quantile)
    return thresh
end

#Get K clusters of facilities (to help branching if needed)
#=
function get_clusters(K)

    CL = Model(Gurobi.Optimizer)
    set_optimizer_attribute(CL, "OutputFlag", 0)
    set_time_limit_sec(CL, 30.0)

    x = @variable(CL, x[i=1:FACILITY_LOCATIONS, k=1:K], Bin)

    #Must be an integer
    city_clust = Int(FACILITY_LOCATIONS/K)
    
    @constraint(CL, UNIQUE[i=1:FACILITY_LOCATIONS], sum(x[i,k] for k in 1:K) == 1)
    @constraint(CL, CITIES[k=1:K], sum(x[i,k] for i in 1:FACILITY_LOCATIONS) == city_clust)
    #@constraint(CL, "all i,j,k" ,z[i,j,k] <= x[i,k])
    #@constraint(CL, "all i,j,k" ,z[i,j,k] <= x[j,k])
    #@constraint(CL, "all i,j,k" ,z[i,j,k] >= x[i,k] + x[j,k] - 1)

    
    @objective(CL, Min, sum(sum(sum(DIST_F[i][j]*x[i,k]*x[j,k] for j in 1:FACILITY_LOCATIONS) for i in 1:FACILITY_LOCATIONS) for k in 1:K))

    optimize!(CL)

    clusters = []
    for k in 1:K
        c_k = []
        for i in 1:FACILITY_LOCATIONS
            if value.(x[i,k]) > 0.001
                push!(c_k, i)
            end
        end
        push!(clusters, c_k)
    end
    
    return clusters
end
#Useful for creating clusters
DIST_F = [[0.0 for j in 1:FACILITY_LOCATIONS] for i in 1:FACILITY_LOCATIONS]
for i in 1:FACILITY_LOCATIONS
    for j in 1:FACILITY_LOCATIONS
        DIST_F[i][j] = dist_facilities[i,j+1]
    end
end
global facilities_cluster_10 = get_clusters(10)
=#

#global THRESHOLD_DISTANCE = get_travel_threshold(QUANTILE)

########################### Getting Facilities for the current group ###########################

#Now that the threshold is defined, we can work on restricted regions so we redefine everything
global group = included_regions[1]
regions = [a for x in included_regions for a in regions_to_state_dict[x]]
global N_REGION = sum([length(regions_to_state_dict[x]) for x in included_regions])
regions_mapping_dict = Dict(zip(collect(1:N_REGION), regions))
num_mapping_dict = Dict(value => key for (key, value) in regions_mapping_dict)
# Region Weights
WEIGHT = [1.00 for i in  1:N_REGION]


#Data for distance to centers and population for each city
city_center = CSV.read("data/vaccine/city_center_dist.csv", DataFrame)
merged_df = CSV.read("data/vaccine/city_loc_pop.csv", DataFrame)

#Pre-processing steps
cities = names(city_center)[2:end]
states = unique(merged_df[:, :state])
states_to_remove = ["Puerto Rico", "Village of Islands"]
states = setdiff(states, states_to_remove)

#First, we get the group associated to each center
centers = city_center[:, :center]
Fac_group = Dict()
for center in centers
    min_index = argmin(collect(city_center[city_center[:, :center] .== center, :][:, Not(:center)][1,:]))
    min_col_name = names(city_center)[min_index + 1]
    state = split(min_col_name, ", ")[2]
    Fac_group[center] = state_to_group[state]
end

#For each state, get every facilities that are within the radius and the population it can serve in each state
C = Dict()
pop_tot = sum(merged_df[!,:population])
for state in regions_to_state_dict[group]
    df_state = unique(merged_df[merged_df[:, :state] .== state, :], :City_state)
    dist_state = city_center[:, vcat(["center"], df_state.City_state)]
    for (i, center) in enumerate(centers)
        if Fac_group[center] == group
            df_center = dist_state[dist_state[:, :center] .== center, :]
            df_center = dropmissing(stack(df_center[:, 2:end]))
            cities = df_center[df_center.value .<= THRESHOLD_DISTANCE, :variable]
            pop = sum(df_state[in.(df_state[:, :City_state], Ref(cities)), :population])
            if pop > 0
                C[(state, i,center)] = pop
            end
        end
    end
end

#Get facilities names
C_keys = sort(collect(keys(C)))

facilities = []
facilities_selected = []

#Select the 20 facilities that we will use in this group
Fac_indexes = Dict()
global index = 1
for state in regions_to_state_dict[group]
    facilities_state = []
    population_state = []
    selected_fac = [t for t in C_keys if state == t[1]]
    for fac in selected_fac
        fac_index = fac[2]
        if (length(facilities_selected) < 20) | (fac_index in facilities_selected)
            push!(facilities_state, fac_index)
            push!(population_state, C[fac])
            if !(fac_index in facilities_selected)
                push!(facilities_selected, fac_index)
                Fac_indexes[index] = fac_index
                global index += 1
            end
        end
        #if !(fac_index in facilities_selected)
        #    push!(facilities_selected, fac_index)
        #end
    end
    push!(facilities, [state, facilities_state, population_state])
end

B_g = Dict("A" => 300000, "B" => 250000, "C" => 325000, "D" => 125000, "E" => 400000, "F" => 325000, "G" => 100000, "H" => 100000, "I" => 500000, "J" => 125000)


FACILITY_LOCATIONS = length(facilities_selected)
N_REGION = length(regions_to_state_dict[group])

TRAVEL_WEIGHT = 0.0
D_MIN = [[25000 for t in 1:T] for i in 1:N_REGION]

#Intervention values and budget
global vaccine_budget = B_g[group]
global num_treatment_vals = Int(vaccine_budget/25000)
TREATMENT_VALS = [(x,) for x in 0:num_treatment_vals]
TREATMENT_BUDGET = [(num_treatment_vals, ) for i in 1:T]
BRANCHING_RANGE = [[[[0, num_treatment_vals]] for t in 1:T] for n in 1:N_REGION]
BRANCHING_RANGE_FACILITY = [2 for j in 1:FACILITY_LOCATIONS]
BRANCHING_RANGE_CLUST_10 = [[0.0, FACILITY_LOCATIONS/10] for i in 1:10]
global vaccine_unit = vaccine_budget / num_treatment_vals

#Define the capacities for the factories (each factory has a bit more than the average budget over the whole country)
vaccine_budget_tot = 50000*51
if (F_TOT == 20) & (FLEXIBILITY == 0)
    cap = ceil(vaccine_budget/(2*25000))*25000
    CAPACITY = [cap for j in 1:FACILITY_LOCATIONS]
end
if (F_TOT == 20) & (FLEXIBILITY == 1)
    cap = ceil(vaccine_budget/(2*25000))*25000 + 25000
    CAPACITY = [cap for j in 1:FACILITY_LOCATIONS]
end
if (F_TOT == 30) & (FLEXIBILITY == 0)
    cap = ceil(vaccine_budget/(3*25000))*25000
    CAPACITY = [cap for j in 1:FACILITY_LOCATIONS]
end
if (F_TOT == 30) & (FLEXIBILITY == 1)
    cap = ceil(vaccine_budget/(3*25000))*25000 + 25000
    CAPACITY = [cap for j in 1:FACILITY_LOCATIONS]
end

#Reset indexes for facilities and update BRANCHING RANGES
global FACILITIES = [[] for i in 1:N_REGION]
global POPULATION = [[] for i in 1:N_REGION]
for i in 1:N_REGION
    for j in 1:FACILITY_LOCATIONS
        if Fac_indexes[j] in facilities[i][2]
            place_j = findall(facilities[i][2] .== Fac_indexes[j])
            push!(FACILITIES[i], j)
            push!(POPULATION[i], ceil(facilities[i][3][place_j][1]/25000)*25000)
        end
    end
    if length(FACILITIES[i]) > 0
        max_i = min(num_treatment_vals, floor(num_treatment_vals*sum(CAPACITY[j] for j in FACILITIES[i])/vaccine_budget))
        BRANCHING_RANGE[i] = [[[0, max_i]] for t in 1:T]
    else
        BRANCHING_RANGE[i] = [[[0, 0]] for t in 1:T]
    end
end

#println("Selected facilities for group ", group, ": ", FACILITIES)

########################### SIR Problem Definition ###########################

# ODE cost function
lambda_cases = 0
# NEED TO SPECIFY
function cost_function(sol, region, t)
    if t == T
        cost = (sol[8] + sol[9] + sol[11] + lambda_cases * sol[2]) * region_population_dict[regions_mapping_dict[region]]
    else
        cost = 0
    end
    return cost
end

# Initial state
delphi_params = CSV.read("data/vaccine/delphi-parameters.csv", DataFrame)
delphi_params_us = delphi_params[delphi_params.Country .== "US", :]
region_parameters_dict = Dict(zip(delphi_params_us.Province, collect(eachrow(Matrix(delphi_params_us[:,6:end])))))
delphi_params = CSV.read("data/vaccine/delphi-parameters.csv", DataFrame)

population = CSV.read("data/vaccine/population.csv", DataFrame)

population_combined = combine(DataFrames.groupby(population, :state),:population => sum)
region_population_dict = Dict(zip(population_combined.state, population_combined.population_sum))

delphi_predictions = CSV.read("data/vaccine/delphi-predictions.csv", DataFrame)
delphi_predictions_us = delphi_predictions[(delphi_predictions.Country .== "US") .& (delphi_predictions.Day .== Dates.Date("2021-02-01")), :]
initial_state = [vcat(Array(delphi_predictions_us[delphi_predictions_us.Province .== region,:][1,5:15]),[0,0,0,0]) for region in regions]
initial_state = [x ./ sum(x) for x in initial_state]

IncubeD = 5
RecoverID = 10
RecoverHD = 15
DetectD = 2
VentilatedD = 10  # Recovery Time when Ventilated
p_v = 0.25  # Percentage of ventilated
p_d = 0.2  # Percentage of infection cases detected.
p_h = 0.03  # Percentage of detected cases hospitalized
vac_effect = 0.85

# NEED TO SPECIFY
function ode_equation!(ds, s, p, t)
    """
    SEIR based model with 16 distinct states, taking into account undetected, deaths, hospitalized and
    recovered, and using an ArcTan government response curve, corrected with a Gaussian jump in case of
    a resurgence in cases
    """
    region = regions_mapping_dict[p[1]]
    t_eff = t + (p[2] - 1) * TSPAN[2]
    alpha, days, r_s, r_dth, p_dth, r_dthdecay, k1, k2, jump, t_jump, std_normal, k3 = region_parameters_dict[region]
    N = region_population_dict[region]
    r_i = log(2) / IncubeD  # Rate of infection leaving incubation phase
    r_d = log(2) / DetectD  # Rate of detection
    r_ri = log(2) / RecoverID  # Rate of recovery not under infection
    r_rh = log(2) / RecoverHD  # Rate of recovery under hospitalization
    r_rv = log(2) / VentilatedD  # Rate of recovery under ventilation
    gamma_t = (
        (2 / pi) * atan(-(t_eff - days) / 20 * r_s) + 1
        + jump * exp(-(t_eff - t_jump) ^ 2 / (2 * std_normal ^ 2))
    )
    p_dth_mod = (2 / pi) * (p_dth - 0.001) * (atan(-t_eff / 20 * r_dthdecay) + pi / 2) + 0.001
    # Equations on main variables
    Vt = p[3] * vaccine_unit / N
    Vt = min(s[1] / vac_effect, Vt)
    ds[1] = -alpha * gamma_t * (s[1] - vac_effect * Vt) * (s[14] + s[3]) - vac_effect * Vt
    ds[2] = alpha * gamma_t * (s[1] - vac_effect * Vt) * (s[14] + s[3]) - r_i * s[2]
    ds[3] = r_i * s[2] - r_d * s[3]
    ds[4] = r_d * (1 - p_dth_mod) * (1 - p_d) * s[3] - r_ri * s[4]
    ds[5] = r_d * (1 - p_dth_mod) * p_d * p_h * s[3] - r_rh * s[5]
    ds[6] = r_d * (1 - p_dth_mod) * p_d * (1 - p_h) * s[3] - r_ri * s[6]
    ds[7] = r_d * p_dth_mod * (1 - p_d) * s[3] - r_dth * s[7]
    ds[8] = r_d * p_dth_mod * p_d * p_h * s[3] - r_dth * s[8]
    ds[9] = r_d * p_dth_mod * p_d * (1 - p_h) * s[3] - r_dth * s[9]
    ds[10] = r_ri * (s[4] + s[6]) + r_rh * s[5]
    ds[11] = r_dth * (s[7] + s[8] + s[9])
    # vaccine states
    ds[12] = - alpha * gamma_t * (s[12] + vac_effect * Vt) * (s[14] + s[3]) + vac_effect * Vt
    ds[13] = alpha * gamma_t * (s[12] + vac_effect * Vt) * (s[14] + s[3]) - r_i * s[13]
    ds[14] = r_i * s[13] - r_d * s[14]
    ds[15] = r_d * s[14]
end 


### Stuff you usually wont touch, just copy over to new application
N_DECISION = length(TREATMENT_VALS[1])
DECISION_PT = [[Tuple(repeat([1], N_DECISION)) for t in 1:T] for p in 1:TOT_PLANS]


# Cost of plans
COST_P = [1.0 for p in 1:TOT_PLANS]
# TODO: harmonize indicators
PLAN_REGION_IND = [0 for p in 1:TOT_PLANS]
PLAN_INFEAS_IND = [true for p in 1:TOT_PLANS]
FACILITY_INFEAS_IND = [false for j in 1:FACILITY_LOCATIONS]
FACILITY_MUST_IND = [false for j in 1:FACILITY_LOCATIONS]
GOOD_BRANCHINGS = true

GLOBAL_BRANCHING_RANGE = deepcopy(BRANCHING_RANGE)
GLOBAL_BRANCHING_RANGE_FACILITY = deepcopy(BRANCHING_RANGE_FACILITY)
GLOBAL_BRANCHING_RANGE_CLUST_10 = deepcopy(BRANCHING_RANGE_CLUST_10)
GLOBAL_COST_P = deepcopy(COST_P)
GLOBAL_DECISION_PT = deepcopy(DECISION_PT)
GLOBAL_PLAN_REGION_IND = deepcopy(PLAN_REGION_IND)
GLOBAL_PLAN_INFEAS_IND = deepcopy(PLAN_INFEAS_IND)
GLOBAL_FACILITY_INFEAS_IND = deepcopy(FACILITY_INFEAS_IND)
GLOBAL_FACILITY_MUST_IND = deepcopy(FACILITY_MUST_IND)
GLOBAL_GOOD_BRANCHINGS = deepcopy(GOOD_BRANCHINGS)

function cost_evaluation(plan)
    cost_master = 0
    for i in 1:N_REGION
        initial_state_region = initial_state[i]
        cost_i = 0
        for t in 1:T
            initial_state_region, cost = solve_ode_exact(initial_state_region, plan[i][t], i, t)
            cost_i = cost_i + cost
        end
        cost_master = cost_master + cost_i
    end
    return cost_master
end
