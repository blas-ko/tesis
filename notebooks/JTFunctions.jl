module JTFunctions

    ######
    using TaylorSeries, TaylorIntegration, Distributions, Plots, DataFrames
    pyplot()
    import TaylorSeries: NumberNotSeries

    export evaluate_neighborhood, evaluate_distribution,
           circle2, square2, ξmax, ξmax_lastT, anal_vs_taylor2D,
                area_of_polygon, separation_rate, remoteness,
           grid_ξmax, grid_FTLE, grid_seprate, vectorField_plot,
           harmonic_oscillator!, simple_pendulum!, artificial_ode!,
           stability_matrix, simplecticity, hp_filter,
           myfonts
    ######

    ##### Plotting attributes #####
    fontXSmall = Plots.font("Helvetica", 9) #,hcenter, :vcenter, 0.0, RGB{N0f8})
    fontSmall = Plots.font("Helvetica", 11)
    fontMed = Plots.font("Helvetica", 12)
    fontBig = Plots.font("Helvetica", 14)
    fontXBig =Plots.font("Helvetica", 16)
    myfonts = Dict(:guidefont=>fontBig, :xtickfont=>fontMed, :ytickfont=>fontMed, :legendfont=>fontSmall)


    ##### Functions & Indicators ####
    # Neighborhood Evaluation
    function evaluate_neighborhood{T<:NumberNotSeries}(δU::Function,ϕ::Taylor1{T},num_vals=100)
        τrange = linspace(0,1,num_vals)
        length(δU(τrange[1])) != 1 ? error("δU is not of the same dimension of the phase space.") : nothing

        return evaluate.(ϕ, δU.(τrange))
    end

    function evaluate_neighborhood{T<:NumberNotSeries}(δU::Function,ϕ::TaylorN{T},num_vals::Integer=100,ξ::Real=0.1)
        τrange = linspace(0,1,num_vals)
        length(δU(τrange[1])) != get_numvars() ? error("δU is not of the same dimension of the phase space.") : nothing
        !(δU(τrange[1]) ≈ δU(τrange[end])) ? error("δU is not a closed surface in the range given.") : nothing

        return evaluate.(ϕ, δU.(τrange,r=ξ))
        end

    function evaluate_neighborhood{T<:AbstractSeries}(δU::Function,ϕ::Array{T,1};num_vals::Integer=100,ξ::Real=0.1)
        return evaluate_neighborhood.(δU,ϕ,num_vals,ξ)
    end


    function evaluate_distribution{T<:NumberNotSeries}(ϕ::TaylorN{T};U::Array{T}=zeros(10,2) )
        distributed_ϕ = Vector{eltype(ϕ)}()

        for i in eachindex(U[:,1])
            push!(distributed_ϕ, ϕ(U[i,:]))
        end

        return distributed_ϕ
    end

        dof = get_numvars()

    function evaluate_distribution{T<:NumberNotSeries}(ϕ::Vector{TaylorN{T}},U)
        return evaluate_distribution.(ϕ,U=U)
    end

    function evaluate_distribution{T<:NumberNotSeries}(ϕ::Array{TaylorN{T},2},dist::Distribution=Normal(0,0.01);num_vals::Integer=200)
        dof = get_numvars()
        U = rand(dist, num_vals, dof)

        return evaluate_distribution(ϕ[:,1],U), evaluate_distribution(ϕ[:,2],U), U
    end

    # Some Neighborhood Parametrization (this should deserve a special type Neighborhood)
    circle2(τ;r=0.1) = [r*cos(2π*τ),r*sin(2π*τ)]
    square2(τ) = nothing

    # Area of Neighborhood
    function area_of_polygon(pjet,qjet)
        #points_per_polygon = length(pjet[1])
        num_time_steps = length(pjet)

        area_per_polygon = zeros(eltype(pjet[1]), num_time_steps)
        for i in 1:num_time_steps

            p_aux = copy(pjet[i])

            p_end = shift!(p_aux)
            push!(p_aux,p_end)

            A_1 = sum(p_aux.*qjet[i])

            q_aux = copy(qjet[i])

            q_end = shift!(q_aux)
            push!(q_aux,q_end)

            A_2 = sum(q_aux.*pjet[i])

            area_per_polygon[i] = (A_1 - A_2)/2.0
        end
        return area_per_polygon
    end

    # Maximum Box Size
    function ξmax(ϕ::Vector{T};ϵ=1e-5) where T<:TaylorN
        dof = length(ϕ)
        ord = ϕ[1].order
        ξ = Inf

        for m in 1:dof
            a_k = ϕ[m].coeffs[ord+1].coeffs

            #In case the last term is zero.
            k = 1
            while a_k == zeros(a_k)
                if k > ord
                    break
                end
                a_k = ϕ[m].coeffs[ord+1-k].coeffs
                k += 1
            end

            for a_jk in a_k
                ξ = min(ξ,abs(ϵ/a_jk)^(1./ord) )
            end
        end

        return ξ
    end

    function ξmax(ϕ::Vector{T};ϵ=1e-5) where T<:Taylor1
        dof = length(ϕ)
        ord = ϕ[1].order
        ξ = Inf

        for m in 1:dof
            a_k = ϕ[m].coeffs[ord+1]

            #In case the last term is zero.
            k = 1
            while a_k == zero(a_k)
                if k > ord
                    break
                end
                a_k = ϕ[m].coeffs[ord+1-k]
                k += 1
            end

            ξ = min(ξ,abs(ϵ/a_k)^(1./ord) )
        end

        return ξ
    end

    function ξmax(ϕ::Matrix{T};ϵ=1e-5) where T<:AbstractSeries

        total_timesteps = size(ϕ)[1]
        ξmax_T = zeros(total_timesteps)

        for t in 1:total_timesteps
            ξmax_T[t] = ξmax(ϕ[t,:];ϵ=ϵ)
        end

        return ξmax_T
    end

    ξmax_lastT(ϕ;ϵ=1e-5) = ξmax(ϕ[end,:],ϵ=ϵ)

    remoteness(ϕμ, Δμ) = sqrt.( (ϕμ[:,1](Δμ) - ϕμ[1,1](Δμ)).^2 + (ϕμ[:,2](Δμ) - ϕμ[1,2](Δμ)).^2 )
    function separation_rate(ϕN;neighborhood_vals::Integer=100)

        ξ_max = ξmax_lastT(ϕN) #should ξ_max be an argument?
        qjet = evaluate_neighborhood(circle2,ϕN[end,1],neighborhood_vals,ξ_max) .- evaluate(ϕN[end,1])
        pjet = evaluate_neighborhood(circle2,ϕN[end,2],neighborhood_vals,ξ_max) .- evaluate(ϕN[end,2])

        P_n = hcat(qjet,pjet)

        P_max = -Inf
        P_min =  Inf

        τ = linspace(0,1,neighborhood_vals)
        θ_max = 0.0
        θ_min = 0.0

        #i_min = 0
        #i_max = 0

        for i in 1:length(qjet)
            P_n_norm = norm(P_n[i,:])

            if P_n_norm > P_max
                P_max = P_n_norm
                θ_max = τ[i]*2π
                #i_max = i
            end

            if P_n_norm < P_min
                P_min = P_n_norm
                θ_min = τ[i]*2π
                #i_min = i
            end
        end

        return P_max/ξ_max, P_min/ξ_max, θ_max, θ_min #, i_max, i_min
    end


    # Compare taylorinteg solution `x,y` vs analytical ones `xa`
    anal_vs_taylor2D(x,y,xa) = sqrt.((x - xa[:,1]).^2 + (y - xa[:,2]).^2)
    # # Compare 2 solutions
    # function JT_accuracy(ϕ,ϕ_JT)
    #     dims = size(ϕ)[2]
    #     diffs = zero(ϕ[:,1])
    #     for dim in 1:dims
    #         diffs += (ϕ[:,dim] - ϕ_JT[:,dim]).^2
    #     end
    #     return sqrt.(diffs)
    # end


    #### PLOTTING & GRIDS ####
    #No parallelization is done yet.

    #ξmax grid without the plot.. should the plot be included?
    #### This should be eliminated after PR is merged
    import TaylorSeries: get_variables
    get_variables(order) = [TaylorN(i,order=order) for i in 1:get_numvars()]
    ####

    function grid_ξmax{T<:Real}(eqs_diff!::Function,t0::T,tmax::T,μ::T;
                        xlim::Tuple=(-1,1),ylim::Tuple=(-1,1),num_points::Integer=30,
                        order_jet::Integer=3,order_taylor::Integer=25,abstol=1e-10)
        @assert get_numvars() == 2 "ξmax must be 2-dimensional."
        δx,δy = get_variables(order_jet)

        xgrid= linspace(xlim...,num_points)
        ygrid= linspace(ylim...,num_points)
        heatgrid = zeros(length(xgrid),length(ygrid))

        L3_ =  -(1 + (5μ/12))
        L2_ = 1 + (μ/3)^(1/3)
        ε₁,ε₂ = (-μ - L3_)/1.5, ( L2_ - (1-μ) )/1.5

        #Parallelize here!
        for (i,x) in enumerate(xgrid)
            for (j,y) in enumerate(ygrid)

                if (norm( [x - (-μ), y] ) > ε₁) && (norm( [x - (1-μ), y] ) > ε₂)
                q0TN = [x+δx,y+δy,0.0,0.0]
                _,ϕN = taylorinteg(eqs_diff!,q0TN,t0,tmax,order_taylor,abstol,maxsteps=800);
                heatgrid[i,j] = ξmax_lastT(ϕN)
                end

            end

        end
        return xgrid, ygrid, heatgrid'
    end

    #FTLE scalar field using TaylorIntegration lyapunov expectrum.
    #TODO: FTLEs could also be made with MY method... (JT of order = 1 jets)
    function grid_FTLE{T<:Real}(eqs_diff!::Function,t0::T,tmax::T,μ::T;
                            xlim::Tuple=(-1,1),ylim::Tuple=(-1,1),num_points::Integer=30,
                            order_taylor::Integer=25,abstol=1e-10)

        qgrid = linspace(xlim...,num_points)
        pgrid = linspace(ylim...,num_points)
        FTLE = zeros(num_points,num_points)

        L3_ =  -(1 + (5μ/12))
        L2_ = 1 + (μ/3)^(1/3)
        ε₁,ε₂ = (-μ - L3_)/1.5, ( L2_ - (1-μ) )/1.5

        #Parallelize here!
        for (i,q) in enumerate(qgrid)
            for (j,p) in enumerate(pgrid)

                if (norm( [x - (-μ), y] ) > ε₁) && (norm( [x - (1-μ), y] ) > ε₂)
                x0 = [q,p]
                _,__,λ = liap_taylorinteg(eqs_diff!,x0,t0,tmax,order_taylor,abstol)
                FTLE[i,j] = maximum(λ[end,:])
                end

            end
        end

        return qgrid, pgrid, FTLE'
    end

    function grid_seprate{T<:Real}(eqs_diff!::Function,t0::T,tmax::T,μ::T;
                        xlim::Tuple=(-1,1),ylim::Tuple=(-1,1),num_points::Integer=30,
                        order_jet::Integer=3,order_taylor::Integer=25,abstol=1e-10,
                        neighborhood_vals::Integer=100)
        @assert get_numvars() == 2 "ξmax must be 2-dimensional."
        δx,δy = get_variables(order_jet)

        #allocation
        #grid for heatmap allocation
        xgrid = linspace(xlim...,num_points)
        ygrid = linspace(ylim...,num_points)
        #matrix allocation for ξmax
        heatgrid_ξmax = zeros(length(xgrid),length(ygrid))
        #matrix allocation for separation rates
        heatgrid_sepRate_max = zeros(length(xgrid),length(ygrid))
        heatgrid_sepRate_min = zeros(length(xgrid),length(ygrid))

        k  = 0
        Δr = max(xgrid.step.hi,ygrid.step.hi)
        #grid allocation for separation rates vector field
        xy_grid = Vector{Tuple{Float64,Float64}}(num_points^2)
        vecField_sepRate_max = Vector{Tuple{Float64,Float64}}(num_points^2)
        vecField_sepRate_min = Vector{Tuple{Float64,Float64}}(num_points^2)

        L3_ =  -(1 + (5μ/12))
        L2_ = 1 + (μ/3)^(1/3)
        ε₁,ε₂ = (-μ - L3_)/1.5, ( L2_ - (1-μ) )/1.5

        #FTLE is missing...

        #Parallelize here!
        for (i,x) in enumerate(xgrid)
            for (j,y) in enumerate(ygrid)

                if (norm( [x - (-μ), y] ) > ε₁) && (norm( [x - (1-μ), y] ) > ε₂)
                    #initial TaylorN condition
                    q0TN = [x+δx,y+δy,0,0]
                    #Jet Trasnport Integration
                    _,ϕN = taylorinteg(eqs_diff!,q0TN,t0,tmax,order_taylor,abstol);
                    #indicators' evaluations
                    ξ_max = ξmax_lastT(ϕN)
                    P_max,P_min,θ_max,θ_min = separation_rate(ϕN,neighborhood_vals=neighborhood_vals)

                    #vector field grids as series of tuples
                    k = num_points*(i-1)+j
                    xy_grid[k] = (x,y)
                    vecField_sepRate_max[k] = (0.45 * Δr) .* ( cos(θ_max), sin(θ_max) )
                    vecField_sepRate_min[k] = (0.45 * Δr) .* ( cos(θ_min), sin(θ_min) )

                    #heatmap matrices
                    heatgrid_ξmax[i,j] = ξ_max
                    heatgrid_sepRate_max[i,j] = P_max
                    heatgrid_sepRate_min[i,j] = P_min
                else
                    k = num_points*(i-1)+j
                    xy_grid[k] = (x,y)
                    vecField_sepRate_max[k] = (0.0, 0.0 )
                    vecField_sepRate_min[k] = (0.0, 0.0 )
                end

            end

        end
        return xgrid, ygrid, heatgrid_ξmax', heatgrid_sepRate_max', heatgrid_sepRate_min', xy_grid, vecField_sepRate_max, vecField_sepRate_min
    end

    #2D vector Field plotting for an TaylorIntegration defined eqs_motion!
    #See some options for beautifying (optional)
    function vectorField_plot(vecField!::Function,t0=0.0;xlim::Tuple=(-1,1),ylim::Tuple=(-1,1),
                              num_points::Int=15,arrowsize::Real=1.2,gridlog::Bool=false)
        X = linspace(xlim...,num_points)
        Y = linspace(ylim...,num_points)

        Δr = max(X.step.hi,Y.step.hi)
        sizeGrid = num_points^2

        #allocation
        xy_grid = Vector{Tuple{Float64,Float64}}(sizeGrid)
        vecField_normed = Vector{Tuple{Float64,Float64}}(sizeGrid)
        normFactor = -Inf
        dx = zeros(Float64,2)

        for (i,x_) in enumerate(X)
            for (j,y_) in enumerate(Y)

                k = num_points*(i-1)+j
                xy_grid[k] = (x_,y_)
                vecField!(t0,xy_grid[k],dx)
                normFactor = max(normFactor, norm(dx))
                vecField_normed[k] = Tuple(arrowsize^2 * Δr * dx)

                if gridlog #sign(f) is because log(-a) not in Real
                    vecField_normed[k] = sign.(vecField_normed[k]).*log.(norm.(vecField_normed[k]).+1)
                end

            end
        end

        if gridlog
            normFactor = log(normFactor+1)
        end

        vecField_normed = [vecField_normed[i]./normFactor for i in eachindex(vecField_normed)]

        #Plotting
        quiver(xy_grid, quiver=vecField_normed)
        xlims!(xlim...)
        ylims!(ylim...)
    end

    function stability_matrix(eqs_diff!::Function,δξ,x0,t0=0.0)
        x0 = x0 .+ δξ
        dx = zeros(x0)
        eqs_diff!(t0,x0,dx)

        dof = length(x0)
        A = zeros(typeof(x0[1]), dof, dof)

        for i in 1:dof
            for j in 1:dof
                A[i,j] = derivative(dx[i],j)
            end
        end

        return A
    end

    simplecticity(ϕ::Vector{T}, ω) where T<:Number = jacobian(ϕ)' * ω * jacobian(ϕ) - ω
    function simplecticity(ϕ::Matrix{T}) where T<:Number

        time_units, D = size(ϕ)
        z_matrix = zeros(D÷2,D÷2)
        ω = hcat(z_matrix, I)
        tmp = hcat(-I, z_matrix)
        ω = vcat(ω, tmp)

        symp = zeros(time_units)
        for t in 1:time_units
            symp[t] = sum(abs,simplecticity(ϕ[t,:],ω))
        end
        return symp
    end

    #### ODE systems ####
    function harmonic_oscillator!(t,x,dx)
        dx[1] = -x[2]
        dx[2] = x[1]
        nothing
    end

    function simple_pendulum!(t,x,dx)
        θ,p = (x[1],x[2])
        dx[1] = p/(m*l^2)
        dx[2] = -m*g*l*sin(θ)
        nothing
    end
    m,g,l = 1.0,1.0,1.0

    function artificial_ode!(t,x,dx)
        dx[1] = 2.0*x[1]*x[2]
        dx[2] = -x[2]^2 + x[1]
        nothing
    end

    ### Other functions... ###
    ### Taken from Sébastien Villemot at http://www.econforge.org/posts/2014/juil./28/cef2014-julia/ ###
    function hp_filter(y::Vector{Float64}, lambda::Int64)
        n = length(y)
        @assert n >= 4

        diag2 = lambda*ones(n-2)
        diag1 = [ -2lambda; -4lambda*ones(n-3); -2lambda ]
        diag0 = [ 1+lambda; 1+5lambda; (1+6lambda)*ones(n-4); 1+5lambda; 1+lambda ]

        D = spdiagm((diag2, diag1, diag0, diag1, diag2), (-2,-1,0,1,2))

        D\y, y - D\y
    end

    function hp_filter(df::T, lambda::Int64) where T <: DataFrame
        num_cols = size(df)[2]
        cycle = Vector{Any}(num_cols) # Vector{Float64}
        trend = Vector{Any}(num_cols)

        i = 1
        for ts in df.columns
            tmp = hp_filter(ts,lambda)
            trend[i] = tmp[1]
            cycle[i] = tmp[2]
            i+=1
        end

        trend = DataFrame(trend,df.colindex)
        cycle = DataFrame(cycle,df.colindex)
        return trend, cycle
    end

end #module
