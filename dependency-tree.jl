using Pkg.TOML, JSON

red(msg)    = println("\033[0;31m$msg\033[0m")
green(msg)  = println("\033[0;32m$msg\033[0m")
yellow(msg) = println("\033[0;33m$msg\033[0m")

function reg_url(pkg)
  return "https://raw.githubusercontent.com/JuliaRegistries/General/master/$(pkg[1])/$pkg/Deps.toml"
end

function jso_pkgs()
  json = JSON.parse(read(`curl https://api.github.com/orgs/JuliaSmoothOptimizers/repos`, String))
  pkgs = map(x -> x["name"], json)
  pkgs = filter(x -> x[end-1:end] == "jl", pkgs)
  pkgs = map(x -> x[1:end-3], pkgs)
  return sort(pkgs)
end

function jso_deps()
  pkgs = jso_pkgs()
  pkgs = setdiff(pkgs, ["qr_mumps", "QPSReader", "SuiteSparseMatrixCollection", "QuadraticModels", "JSOSuite"])
  #pkgs = ["LinearOperators", "Krylov", "NLPModels", "NLPModelsIpopt", "CUTEst"]
  deps = dependency_tree(pkgs, limitto=pkgs)
  return deps
end

dependency_tree(pkg :: String; limitto=[]) = dependency_tree([pkg], limitto=limitto)

function dependency_tree(pkgs :: Array{<: String}; limitto=[])
  todo = copy(pkgs)
  deps = Dict()
  versions = Dict()
  ignored = String[]
  fname = tempname()
  while length(todo) > 0
    pkg = pop!(todo)
    green("Processing $pkg")
    url = reg_url(pkg)
    try
      download(url, fname)
      download(replace(url, "Deps" => "Versions"), fname * "_v")
    catch ex
      yellow("$pkg not found in Registry, possible a stdlib package")
      deps[pkg] = []
      push!(ignored, pkg)
      continue
    end
    toml = TOML.parsefile(fname)
    dep_pkgs = String[]
    for p in keys.(values(toml))
      append!(dep_pkgs, p)
    end
    if length(limitto) > 0
      dep_pkgs = dep_pkgs ∩ limitto
    end
    deps[pkg] = dep_pkgs
    for p in dep_pkgs
      if p == "Homebrew"
        println(dep_pkgs)
        println(limitto)
      end
      if !(p in keys(deps)) && !(p in ignored)
        push!(todo, p)
      end
    end
    versions[pkg] = sort(VersionNumber.(keys(TOML.parsefile(fname * "_v"))))[end]
  end
  return deps, versions
end

function depth_computation(deps :: Dict)
  pkgs = sort(collect(keys(deps)))
  n = length(pkgs)
  depth = zeros(Int, n)

  function depth_update(i, v)
    if depth[i] ≥ v
      depth[i] = v
      J = indexin(deps[pkgs[i]], pkgs)
      for j in J
        depth_update(j, v - 1)
      end
      return true
    else
      return false
    end
  end

  # Find feasible depth
  for i = 1:n
    depth_update(i, 0)
  end
  # Increase for positivity
  depth .+= -minimum(depth)

  done = false
  while !done
    done = true
    for i = 1:n
      J = indexin(deps[pkgs[i]], pkgs)
      d = if length(J) == 0
        0
      else
        max(0, maximum(depth[J]) + 1)
      end
      if depth[i] > d
        depth[i] = d
        done = false
      end
    end
  end

  return depth
end

function weight_computation(deps, depth)
  pkgs = sort(collect(keys(deps)))
  n = length(pkgs)
  weight = ones(Int, n)
  for d = maximum(depth):-1:0
    for i = findall(depth .== d)
      J = indexin(deps[pkgs[i]], pkgs)
      weight[J] .+= weight[i]
    end
  end
  return weight
end

function tikz_draw(deps, depth, weight, versions)
  pkgs = sort(collect(keys(deps)))
  #S = sortperm(weight)
  #depth = depth[S]
  #pkgs  = pkgs[S]
  open("tree.tex", "w") do f
    println(f, "\\begin{tikzpicture}")
    M = maximum(depth)
    for d = 0:M
      J = findall(depth .== d)
      for (c,j) = enumerate(J)
        pkg = replace(pkgs[j], "_" => "\\_")
        v = versions[pkgs[j]]
        san = lowercase(replace(pkgs[j], "_" => ""))
        x = 6d
        y = -10 * (c - 1) / (length(J) - 1)
        println(f, "\\node[draw,fill=white] ($san) at ($x,$y) {$pkg - $v};")
      end
    end
    println(f, "\\begin{scope}[on background layer]")
    for (i,pkg) in enumerate(pkgs)
      J = indexin(deps[pkg], pkgs)
      san_dest = lowercase(replace(pkg, "_" => ""))
      for j in J
        san_orig = lowercase(replace(pkgs[j], "_" => ""))
        Δd = abs(depth[j] - depth[i])
        println(f, "\\draw[->,gray] ($san_orig) to [in=180,out=0,looseness=0.3] ($san_dest);")
      end
    end
    println(f, "\\end{scope}")
    println(f, "\\end{tikzpicture}")
  end
end

#deps = dependency_tree("NLPModels")
#pkgs = jso_pkgs()
#deps, versions = jso_deps()
depth = depth_computation(deps)
weight = weight_computation(deps, depth)
tikz_draw(deps, depth, weight, versions)
