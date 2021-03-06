function build_model(estimator::Estimators, PID::Vector{Vector{Int64}}, TID::Vector{Vector{Int64}}, Effect::Symbol, X::Matrix{Float64}, y::Vector{Float64}, varlist::Vector{String}, Categorical::Vector{Bool}, Intercept::Bool; short::Bool = false)
	N = ModelValues_N(size(X, 1))
	if Effect == :Panel
		X = transform(estimator, PID, X, Categorical, Intercept)
		y = transform(estimator, PID, y)
	elseif Effect == :Temporal
		X = transform(estimator, TID, X, Categorical, Intercept)
		y = transform(estimator, TID, y)
	elseif Effect == :TwoWays
		X = transform(estimator, vcat([PID], [TID]), X, Categorical, Intercept)
		y = transform(estimator, vcat([PID], [TID]), y)
	end
	X, LinearIndependent = get_fullrank(X)
	X = ModelValues_X(X)
	y = ModelValues_y(y)
	nobs = ModelValues_nobs(y)
	PID = transformID(estimator, PID)
	PID = ModelValues_PanelID(PID)
	TID = transformID(estimator, TID)
	TID = ModelValues_TemporalID(TID)
	T = ModelValues_T(PID)
	n = ModelValues_n(PID)
	Bread = ModelValues_Bread(X)
	β = ModelValues_β(X, Bread, y)
	ŷ = ModelValues_ŷ(X, β)
	û = ModelValues_û(y, ŷ)
	mdf = length(get(β)) - Intercept
	if isa(estimator, FE)
		if Effect == :Panel
			mdf += length(get(PID)) - 1
		elseif Effect == :Temporal
			mdf += length(get(TID)) - 1
		elseif Effect == :TwoWays
			mdf += length(get(PID)) + length(get(TID)) - 2
		end
	end
	mdf = ModelValues_dof(mdf)
	rdf = ModelValues_rdf(get(nobs) - get(mdf) - Intercept)
	RSS = ModelValues_RSS(û)
	MRSS = ModelValues_MRSS(RSS, rdf)
	if short
		if isa(estimator, BE)
			return MRSS, X, y
		elseif isa(estimator, FE)
			return MRSS, T, nobs, N, n, PID, TID
		end
	end
	varlist = varlist[find(LinearIndependent)]
	varlist = ModelValues_Varlist(varlist)
	idiosyncratic = ModelValues_Idiosyncratic(zero(Float64))
	individual = ModelValues_Individual(MRSS,
								idiosyncratic,
								T)
	θ = ModelValues_θ(idiosyncratic, individual, PID)
	return PID, TID, X, Bread, y, β, varlist, ŷ, û, nobs, N, n, T, mdf, rdf, RSS, MRSS, individual, idiosyncratic, θ
end
function build_model(estimator::RE, PID::Vector{Vector{Int64}}, TID::Vector{Vector{Int64}}, Effect::Symbol, X::Matrix{Float64}, y::Vector{Float64}, varlist::Vector{String}, Categorical::Vector{Bool}, Intercept::Bool)
	MRSS_be, X̄, ȳ = build_model(BE(), PID, TID, Effect, X, y, varlist, Categorical, Intercept, short = true)
	MRSS_fe, T, nobs, N, n, Effect, TID = build_model(FE(), PID, TID, Effect, X, y, varlist, Categorical, Intercept, short = true)
	idiosyncratic = ModelValues_Idiosyncratic(get(MRSS_fe))
	T = ModelValues_T(T)
	individual = ModelValues_Individual(MRSS_be, idiosyncratic, T)
	PID = ModelValues_PanelID(PID)
	θ = ModelValues_θ(idiosyncratic, individual, PID)
	Lens = length.(get(PID))
	X = transform(X, X̄, θ, Lens)
	X, LinearIndependent = get_fullrank(X)
	X = ModelValues_X(X)
	y -= mapreduce(times_row -> repeat([ last(times_row) ], inner = first(times_row)), vcat, Iterators.zip(Lens, get(ȳ) .* get(θ)))
	y = ModelValues_y(y)
	varlist = ModelValues_Varlist(varlist[LinearIndependent])
	Bread = ModelValues_Bread(X)
	β = ModelValues_β(X, Bread, y)
	ŷ = ModelValues_ŷ(X, β)
	û = ModelValues_û(y, ŷ)
	mdf = ModelValues_dof(length(get(β)) - Intercept)
	rdf = ModelValues_rdf(get(nobs) - get(mdf) - Intercept)
	RSS = ModelValues_RSS(û)
	MRSS = ModelValues_MRSS(RSS, rdf)
	return PID, TID, X, Bread, y, β, varlist, ŷ, û, nobs, N, n, T, mdf, rdf, RSS, MRSS, individual, idiosyncratic, θ
end
function build_model(estimator::Estimators, PID::Vector{Vector{Int64}}, TID::Vector{Vector{Int64}}, Effect::Symbol, X::Matrix{Float64}, z::Matrix{Float64}, Z::Matrix{Float64}, y::Vector{Float64}, varlist::Vector{String}, Categorical::Vector{Bool}, CategoricalIV::Vector{Bool}, Intercept::Bool; short::Bool = false)
	N = ModelValues_N(size(X, 1))
	if Effect == :Panel
		X = transform(estimator, PID, X, Categorical, Intercept)
		Z = transform(estimator, PID, Z, CategoricalIV, false)
		z = transform(estimator, PID, z, Vector{Bool}(), false)
		y = transform(estimator, PID, y)
	elseif Effect == :Temporal
		X = transform(estimator, TID, X, Categorical, Intercept)
		Z = transform(estimator, TID, Z, CategoricalIV, false)
		z = transform(estimator, TID, z, Vector{Bool}(), false)
		y = transform(estimator, TID, y)
	elseif Effect == :TwoWays
		X = transform(estimator, vcat([PID], [TID]), X, Categorical, Intercept)
		Z = transform(estimator, vcat([PID], [TID]), Z, CategoricalIV, false)
		z = transform(estimator, vcat([PID], [TID]), z, Vector{Bool}(), false)
		y = transform(estimator, vcat([PID], [TID]), y)
	end
	x = hcat(X, Z)
	x, LinearIndependent = get_fullrank(x)
	Bread = inv(cholfact(x' * x))
	δ = mapslices(col -> Bread * x' * col, z, 1)
	ẑ = mapslices(δ -> x * δ, δ, 1)
	X̂ = hcat(X, ẑ)
	X̃ = hcat(X, z)
	X̂, LinearIndependent = get_fullrank(X̂)
	X̃ = X̃[:,LinearIndependent]
	X̂ = ModelValues_X(X̂)
	X̃ = ModelValues_X(X̃)
	Bread = ModelValues_Bread(X̂)
	y = ModelValues_y(y)
	nobs = ModelValues_nobs(y)
	PID = transformID(estimator, PID)
	PID = ModelValues_PanelID(PID)
	TID = transformID(estimator, TID)
	TID = ModelValues_TemporalID(TID)
	T = ModelValues_T(PID)
	n = ModelValues_n(PID)
	β = ModelValues_β(X̂, Bread, y)
	ŷ = ModelValues_ŷ(X̃, β)
	û = ModelValues_û(y, ŷ)
	mdf = length(get(β)) - Intercept
	if isa(estimator, FE)
		if Effect == :Panel
			mdf += length(get(PID)) - 1
		elseif Effect == :Temporal
			mdf += length(get(TID)) - 1
		elseif Effect == :TwoWays
			mdf += length(get(PID)) + length(get(TID)) - 2
		end
	end
	mdf = ModelValues_dof(mdf)
	rdf = ModelValues_rdf(get(nobs) - get(mdf) - Intercept)
	RSS = ModelValues_RSS(û)
	MRSS = ModelValues_MRSS(RSS, rdf)
	if short
		if isa(estimator, BE)
			return MRSS, X, Z, z, y
		elseif isa(estimator, FE)
			return MRSS, T, nobs, N, n, PID, TID
		end
	end
	varlist = varlist[find(LinearIndependent[1:length(varlist)])]
	varlist = ModelValues_Varlist(varlist)
	idiosyncratic = ModelValues_Idiosyncratic(zero(Float64))
	individual = ModelValues_Individual(MRSS,
								idiosyncratic,
								T)
	θ = ModelValues_θ(idiosyncratic, individual, PID)
	return PID, TID, X̂, Bread, y, β, varlist, ŷ, û, nobs, N, n, T, mdf, rdf, RSS, MRSS, individual, idiosyncratic, θ
end
function build_model(estimator::RE, PID::Vector{Vector{Int64}}, TID::Vector{Vector{Int64}}, Effect::Symbol, X::Matrix{Float64}, z::Matrix{Float64}, Z::Matrix{Float64}, y::Vector{Float64}, varlist::Vector{String}, Categorical::Vector{Bool}, CategoricalIV::Vector{Bool}, Intercept::Bool)
	MRSS_be, X̄, Z̄, z̄, ȳ = build_model(BE(), PID, TID, Effect, X, z, Z, y, varlist, Categorical, CategoricalIV, Intercept, short = true)
	MRSS_fe, T, nobs, N, n, Effect, TID = build_model(FE(), PID, TID, Effect,  X, z, Z, y, varlist, Categorical, CategoricalIV, Intercept, short = true)
	idiosyncratic = ModelValues_Idiosyncratic(get(MRSS_fe))
	T = ModelValues_T(T)
	individual = ModelValues_Individual(MRSS_be, idiosyncratic, T)
	PID = ModelValues_PanelID(PID)
	Lens = length.(get(PID))
	θ = ModelValues_θ(idiosyncratic, individual, PID)
	X̄ .*= get(θ)
	Z̄ .*= get(θ)
	z̄ .*= get(θ)
	X -= mapreduce(times_row -> repmat(last(times_row)', first(times_row), 1), vcat, Iterators.zip(Lens, map(idx -> X̄[idx,:], 1:size(X̄, 1))))
	Z -= mapreduce(times_row -> repmat(last(times_row)', first(times_row), 1), vcat, Iterators.zip(Lens, map(idx -> Z̄[idx,:], 1:size(Z̄, 1))))
	z -= mapreduce(times_row -> repmat(last(times_row)', first(times_row), 1), vcat, Iterators.zip(Lens, map(idx -> z̄[idx,:], 1:size(z̄, 1))))
	y -= mapreduce(times_row -> repeat([ last(times_row) ], inner = first(times_row)), vcat, Iterators.zip(Lens, get(ȳ) .* get(θ)))
	x = hcat(X, Z)
	Bread = inv(cholfact(x' * x))
	δ = mapslices(col -> Bread * x' * col, z, 1)
	ẑ = mapslices(δ -> x * δ, δ, 1)
	X̂ = hcat(X, ẑ)
	X̃ = hcat(X, z)
	X̂, LinearIndependent = get_fullrank(X̂)
	X̃ = X̃[:,LinearIndependent]
	X̂ = ModelValues_X(X̂)
	X̃ = ModelValues_X(X̃)
	y = ModelValues_y(y)
	varlist = ModelValues_Varlist(varlist[find(LinearIndependent[1:length(varlist)])])
	Bread = ModelValues_Bread(X̂)
	β = ModelValues_β(X̂, Bread, y)
	ŷ = ModelValues_ŷ(X̃, β)
	û = ModelValues_û(y, ŷ)
	mdf = ModelValues_dof(length(get(β)) - Intercept)
	rdf = ModelValues_rdf(get(nobs) - get(mdf) - Intercept)
	RSS = ModelValues_RSS(û)
	MRSS = ModelValues_MRSS(RSS, rdf)
	return PID, TID, X̂, Bread, y, β, varlist, ŷ, û, nobs, N, n, T, mdf, rdf, RSS, MRSS, individual, idiosyncratic, θ
end
