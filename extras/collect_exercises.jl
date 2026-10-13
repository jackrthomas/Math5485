#!/usr/bin/env julia
"""
collect_exercises.jl

Collects all exercises from lecture notebooks (L##.ipynb) and writes them
to a single Quarto .qmd output file, using .exercise-box div syntax
compatible with random-2.ipynb.

Skips L00.ipynb.

Quizzes: every `Q<n>.qmd` in exercises/quizzes is inserted after the lecture given by
its `after-lecture:` front matter field. Each top-level `::: {.quiz-question}` block
becomes an exercise labelled "Quiz <n>: Exercise <k>" whose solution is available in
the bank immediately (`release="now"`).

Problem classes: every `PC<n>.ipynb` in "exercises/Problem classes" is read the same
way as a lecture notebook (its `::: {#exr-...}` blocks are pulled out) and inserted
after the lecture given by its `after-lecture:` YAML front matter, which must sit in
the notebook's first cell. They get their own "Problem Class <n>" section so they never
affect the numbering of the "Lecture <n>" sections around them. Their exercises are
labelled "Exercise 1", "Exercise 2", ... (the notebook isn't on the website, so `@exr-...`
cross-references to it wouldn't resolve) and carry `release-date="<date>"` from the
front matter's `date:` field, so the bank releases their solutions a week after the
problem class.

Embeds all code cell outputs (plots, text, HTML) as inline content.

Runs automatically before every `quarto render` (pre-render in _quarto.yml, via
extras/run-collect-exercises.py). exercises.qmd is only rewritten when it changes,
so `quarto preview` doesn't keep re-rendering.

Usage (by hand, from anywhere):
    julia extras/collect_exercises.jl
"""

using JSON
using Base64

# ── Configuration ─────────────────────────────────────────────────────────────
# paths are relative to this script, so it can be run from any directory
const root          = joinpath(@__DIR__, "..")
lectures_dir        = joinpath(root, "lectures")
quizzes_dir         = joinpath(root, "exercises", "quizzes")
problem_classes_dir = joinpath(root, "exercises", "Problem classes")
output_file         = joinpath(root, "exercises", "exercises.qmd")

# ── Helpers ───────────────────────────────────────────────────────────────────

"""
    cell_to_markdown(cell, lang) -> String

Convert a single notebook cell to a Markdown string.
- Markdown cells: returned as-is.
- Code cells: source in a collapsible fenced block, followed by all outputs:
  image/png and image/svg+xml as base64 img, text/html as raw HTML,
  text/plain and stream as fenced code blocks.
"""
function cell_to_markdown(cell, lang::String="julia")::String
    buf = IOBuffer()
    src = join(cell["source"])
    isempty(strip(src)) && return ""

    if cell["cell_type"] == "markdown"
        println(buf, src)
    else  # code / raw
        # drop Quarto cell options (`#| code-fold: true`, ...): they mean nothing in the bank
        code = join(filter(l -> !startswith(lstrip(l), "#|"), split(src, '\n')), '\n')
        code = strip(code, '\n')
        println(buf, "<details><summary>Code</summary>\n")
        println(buf, "```$lang")
        println(buf, code)
        println(buf, "```")
        println(buf, "</details>\n")

        # Embed all outputs produced by this cell
        for output in get(cell, "outputs", [])
            data = get(output, "data", Dict())

            if haskey(data, "image/png")
                b64 = replace(string(data["image/png"]), '\n' => "")
                println(buf, "\n<img src=\"data:image/png;base64,$b64\" style=\"max-width:100%;height:auto;display:block;margin:.5em 0;\">")

            elseif haskey(data, "image/svg+xml")
                # embed as an image (inlining the svg itself can clash with other svgs' ids)
                svg = join(data["image/svg+xml"])
                println(buf, "\n<img src=\"data:image/svg+xml;base64,$(base64encode(svg))\" style=\"max-width:100%;height:auto;display:block;margin:.5em 0;\">")

            elseif haskey(data, "text/html")
                html = join(data["text/html"])
                println(buf, "\n$html")

            elseif haskey(data, "text/plain")
                txt = join(data["text/plain"])
                println(buf, "\n```\n$txt\n```")

            elseif get(output, "output_type", "") == "stream"
                txt = join(get(output, "text", []))
                isempty(strip(txt)) || println(buf, "\n```\n$txt\n```")
            end
        end
    end

    return String(take!(buf))
end

"""
    notebook_to_markdown(path) -> String
    notebook_to_markdown(cells, lang) -> String

Convert a Jupyter notebook (or a slice of its cells) to a single Markdown string.
"""
function notebook_to_markdown(cells, lang::String)::String
    buf = IOBuffer()
    for cell in cells
        md = cell_to_markdown(cell, lang)
        isempty(md) && continue
        println(buf, md)
    end
    return String(take!(buf))
end

function notebook_to_markdown(path::String)::String
    nb   = JSON.parsefile(path)
    lang = get(get(get(nb, "metadata", Dict()), "kernelspec", Dict()), "language", "julia")
    return notebook_to_markdown(nb["cells"], lang)
end

"""
    extract_exercises(markdown, lecture_label) -> Vector{String}

Pull every `::: {#exr-...}` block out of markdown and re-wrap as
`::: {.exercise-box #bank-exr-...}` with a bold cross-reference label.
Extra attributes are kept, e.g. `::: {#exr-1 .no-solution}` marks an exercise
that doesn't need a solution (it is not counted as missing in the exercise report).
Nested `:::` blocks (hints, solutions) are preserved.
Trailing outputs immediately after closing ::: are pulled into the block.
"""
function extract_exercises(markdown::String, lecture_label::String)::Vector{String}
    exercises = String[]
    lines     = split(markdown, '\n')
    n         = length(lines)
    i         = 1

    while i <= n
        line = lines[i]
        m = match(r"^:::\s*\{#(exr-[\w-]+)([^}]*)\}", line)
        if m !== nothing
            exr_id = m.captures[1]
            extra  = strip(m.captures[2])   # e.g. `.no-solution` (exercise doesn't need a solution)
            depth  = 1
            i     += 1

            # Collect inner lines until matching closing :::
            inner = String[]
            while i <= n && depth > 0
                l = lines[i]
                if occursin(r"^:::\s*\{", l)
                    depth += 1
                    push!(inner, l)
                elseif strip(l) == ":::"
                    depth -= 1
                    depth > 0 && push!(inner, l)
                else
                    push!(inner, l)
                end
                i += 1
            end

            # Remove bank/practice links (redundant inside the bank)
            inner = filter(l -> !occursin("bank.html", l) && !occursin("random-2.html", l), inner)

            # Strip leading/trailing blank lines
            while !isempty(inner) && isempty(strip(first(inner))); popfirst!(inner); end
            while !isempty(inner) && isempty(strip(last(inner)));  pop!(inner);      end

            # Remove equation numbers
            inner = map(inner) do line
                line = replace(line, r"\s*\{#eq-[\w-]+\}" => "")
                line = replace(line, r"\\tag\{[^}]*\}"    => "")
                line
            end

            # Peek ahead: grab outputs immediately following closing :::
            trailing = String[]
            j = i
            while j <= n
                l = strip(lines[j])
                if isempty(l)
                    j += 1
                elseif startswith(l, "<img ") || (startswith(l, "<") && !startswith(l, "<details>") && !startswith(l, "</details>"))
                    push!(trailing, lines[j])
                    j += 1
                elseif l == "```"
                    push!(trailing, lines[j]); j += 1
                    while j <= n && strip(lines[j]) != "```"
                        push!(trailing, lines[j]); j += 1
                    end
                    j <= n && (push!(trailing, lines[j]); j += 1)
                else
                    break
                end
            end
            if !isempty(trailing)
                i = j
                append!(inner, ["", trailing...])
            end

            block = "<!-- $lecture_label -->\n" *
                    "::: {.exercise-box #bank-$exr_id$(isempty(extra) ? "" : " " * extra)}\n" *
                    "**@$exr_id**\n\n" *
                    join(inner, '\n') * "\n" *
                    ":::"

            push!(exercises, block)
        else
            i += 1
        end
    end
    return exercises
end

"""
    parse_after_lecture(text, filename) -> Int

Extract the `after-lecture:` field from a `---`-delimited YAML front matter
block at the start of `text`. Shared by quiz `.qmd` files and problem-class
notebooks. Errors if the front matter or the field is missing.
"""
function parse_after_lecture(text::String, filename::String)::Int
    text = replace(text, "\r\n" => "\n")  # normalize CRLF so the front-matter regex matches
    fm    = match(r"^---\n(.*?)\n---[ \t]*(?:\n|$)"s, text)  # closing `---` may end the text (notebook cells)
    after = fm === nothing ? nothing : match(r"^after-lecture:\s*(\d+)"m, fm.captures[1])
    after === nothing && error("$filename: missing `after-lecture:` in the front matter")
    return parse(Int, after.captures[1])
end

"""
    read_quiz(path) -> (number, after_lecture, blocks)

Read a quiz file `Q<n>.qmd` and turn each top-level `::: {.quiz-question}` block
into an exercise-box labelled "Quiz <n>: Exercise <k>" (solutions released immediately).
"""
function read_quiz(path::String)
    quiz_num      = parse(Int, match(r"^Q(\d+)\.qmd$", basename(path)).captures[1])
    text          = replace(read(path, String), "\r\n" => "\n")
    after_lecture = parse_after_lecture(text, basename(path))

    fm   = match(r"^---\n(.*?)\n---\n"s, text)
    body = fm === nothing ? text : text[length(fm.match)+1:end]
    body = replace(body, r"<!--.*?-->"s => "")      # drop comments

    blocks = String[]
    lines  = split(body, '\n')
    i      = 1
    while i <= length(lines)
        if occursin(r"^:::\s*\{\s*\.quiz-question", lines[i])
            depth, inner = 1, String[]
            i += 1
            while i <= length(lines) && depth > 0
                l = lines[i]
                if occursin(r"^:::\s*\{", l)
                    depth += 1
                elseif strip(l) == ":::"
                    depth -= 1
                end
                depth > 0 && push!(inner, l)
                i += 1
            end
            while !isempty(inner) && isempty(strip(first(inner))); popfirst!(inner); end
            while !isempty(inner) && isempty(strip(last(inner)));  pop!(inner);      end

            k = length(blocks) + 1
            push!(blocks, "<!-- Q$quiz_num -->\n" *
                          "::: {.exercise-box #bank-q$quiz_num-$k release=\"now\"}\n" *
                          "**Quiz $quiz_num: Exercise $k**\n\n" *
                          join(inner, '\n') * "\n" *
                          ":::")
        else
            i += 1
        end
    end
    return quiz_num, after_lecture, blocks
end

"""
    read_problem_class(path) -> (number, after_lecture, exercises)

Read a problem-class notebook `PC<n>.ipynb` the same way a lecture notebook is
read (its `::: {#exr-...}` blocks are pulled out via `extract_exercises`), taking
`after-lecture:` and `date:` from the YAML front matter in the notebook's first cell.
Labelled "PC<n>" (not the lecture label) so it lands in its own "Problem Class <n>"
section and never disturbs the numbering of surrounding "Lecture <n>" sections.
The exercises are relabelled "Exercise <k>" and tagged `release-date="<date>"`.
"""
function read_problem_class(path::String)
    pc_num = parse(Int, match(r"^PC(\d+)\.ipynb$", basename(path)).captures[1])
    nb     = JSON.parsefile(path)
    cells  = nb["cells"]
    isempty(cells) && error("$(basename(path)): notebook has no cells")

    front_matter  = join(cells[1]["source"])
    after_lecture = parse_after_lecture(front_matter, basename(path))
    date = match(r"^date:\s*[\"']?(\d{4}-\d{2}-\d{2})"m, front_matter)
    date === nothing && error("$(basename(path)): missing `date:` (yyyy-mm-dd) in the front matter")

    lang      = get(get(get(nb, "metadata", Dict()), "kernelspec", Dict()), "language", "julia")
    label     = "PC$pc_num"
    markdown  = notebook_to_markdown(cells[2:end], lang)
    exercises = extract_exercises(markdown, label)

    # "Exercise 1", "Exercise 2", ... in place of the `@exr-...` cross-reference, and
    # solutions released a week after the problem class (see solutionReleaseTime in bank.ipynb)
    exercises = map(enumerate(exercises)) do (k, ex)
        ex = replace(ex, r"^\*\*@exr-[\w-]+\*\*$"m => "**Exercise $k**"; count=1)
        replace(ex, r"^(::: \{\.exercise-box #[\w-]+)"m => SubstitutionString("\\1 release-date=\"$(date[1])\""); count=1)
    end

    return pc_num, after_lecture, exercises
end

"""
    write_quizzes(io, quizzes)

Write each quiz as a `## Quiz <n>` section.
"""
function write_quizzes(io, quizzes)
    for (quiz_num, _, blocks) in quizzes
        println("  Q$quiz_num: $(length(blocks)) question(s)")
        println(io, "## Quiz $quiz_num\n")
        for b in blocks
            println(io, b)
            println(io)
        end
    end
end

"""
    write_problem_classes(io, problem_classes)

Write each problem class as a `## Problem Class <n>` section.
"""
function write_problem_classes(io, problem_classes)
    for (pc_num, _, exercises) in problem_classes
        if isempty(exercises)
            println("  PC$pc_num: no exercises found")
        else
            println("  PC$pc_num: $(length(exercises)) exercise(s)")
            println(io, "## Problem Class $pc_num\n")
            for ex in exercises
                println(io, ex)
                println(io)
            end
        end
    end
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main()
    pattern   = r"^L\d+\.ipynb$"
    all_files = filter(f -> occursin(pattern, f), readdir(lectures_dir))
    sort!(all_files)
    all_files = filter(f -> f != "L00.ipynb", all_files)

    if isempty(all_files)
        @warn "No lecture notebooks found in $lectures_dir"
        return
    end

    println("Found $(length(all_files)) lecture notebook(s): $(join(all_files, ", "))")

    quiz_files = isdir(quizzes_dir) ? filter(f -> occursin(r"^Q\d+\.qmd$", f), readdir(quizzes_dir)) : String[]
    quizzes    = sort([read_quiz(joinpath(quizzes_dir, f)) for f in quiz_files])
    println("Found $(length(quizzes)) quiz file(s)")

    pc_files        = isdir(problem_classes_dir) ? filter(f -> occursin(r"^PC\d+\.ipynb$", f), readdir(problem_classes_dir)) : String[]
    problem_classes = sort([read_problem_class(joinpath(problem_classes_dir, f)) for f in pc_files])
    println("Found $(length(problem_classes)) problem class notebook(s)")

    written    = Set{Int}()
    written_pc = Set{Int}()

    mkpath(dirname(output_file))
    io = IOBuffer()
    begin
        write(io, """
---
format:
  html:
    code-copy: true
    toc: true
---

""")

        for fname in all_files
            label   = splitext(fname)[1]
            num_str = replace(label, r"^L0*" => "")
            lec_num = tryparse(Int, num_str)

            path      = joinpath(lectures_dir, fname)
            markdown  = notebook_to_markdown(path)
            exercises = extract_exercises(markdown, label)

            if isempty(exercises)
                println("  $label: no exercises found")
            else
                println("  $label: $(length(exercises)) exercise(s)")
                println(io, "## Lecture $lec_num\n")
                for ex in exercises
                    println(io, ex)
                    println(io)
                end
            end

            # quizzes and problem classes that come after this lecture
            after_this = filter(q -> q[2] == lec_num, quizzes)
            write_quizzes(io, after_this)
            union!(written, first.(after_this))

            pc_after_this = filter(p -> p[2] == lec_num, problem_classes)
            write_problem_classes(io, pc_after_this)
            union!(written_pc, first.(pc_after_this))
        end

        # quizzes/problem classes after a lecture that doesn't exist (yet) go at the end
        write_quizzes(io, filter(q -> !(q[1] in written), quizzes))
        write_problem_classes(io, filter(p -> !(p[1] in written_pc), problem_classes))
    end

    # only touch the file when something changed (avoids needless re-renders in quarto preview)
    new = String(take!(io))
    if isfile(output_file) && read(output_file, String) == new
        println("\nExercises unchanged: $output_file")
    else
        write(output_file, new)
        println("\nWrote exercises to: $output_file")
    end
end

main()
