# Pre-render step (see _quarto.yml): rebuild exercises/exercises.qmd from the lectures,
# quizzes and problem classes by running extras/collect_exercises.jl.
#
#     julia --startup-file=no --project=extras extras/run-collect-exercises.jl
#
# Uses the tools environment in extras/ (Project.toml: JSON for collect_exercises.jl).
# Skipped (it takes several seconds, mostly Julia compiling the script) when none of its inputs
# changed since the last run; set COLLECT_EXERCISES_FORCE=1 to run it anyway.

const here   = @__DIR__
const root   = dirname(here)
const script = joinpath(here, "collect_exercises.jl")
const stamp  = joinpath(root, ".quarto", "collect-exercises.stamp")
const output = joinpath(root, "exercises", "exercises.qmd")

# everything collect_exercises.jl reads (the folders too, so that adding or removing a file counts)
const dirs   = [joinpath(root, d) for d in ("lectures", "exercises/quizzes", "exercises/Problem classes", "exercises/past-papers")]
const inputs = vcat([script, @__FILE__], dirs,
                    [joinpath(d, f) for d in dirs if isdir(d) for f in readdir(d)])

function up_to_date()
    if haskey(ENV, "COLLECT_EXERCISES_FORCE") || !(isfile(stamp) && isfile(output) &&
                                                  isdir(joinpath(root, "exercises", "bank-media")))
        return false
    end
    # the stamp holds the start time of the last successful run (an older, empty stamp: its mtime)
    t = something(tryparse(Float64, strip(read(stamp, String))), mtime(stamp))
    return all(mtime(f) < t for f in inputs if ispath(f))
end

if up_to_date()
    println("collect_exercises: inputs unchanged, exercises/exercises.qmd is up to date")
    exit(0)
end

start = time()
# a fresh process, so that the script runs exactly as it does by hand
ok = success(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$here $script`; stdout, stderr))
if ok   # dated to the start, so that files saved during the run count as changed next time
    mkpath(dirname(stamp))
    write(stamp, string(start))
end
exit(ok ? 0 : 1)
