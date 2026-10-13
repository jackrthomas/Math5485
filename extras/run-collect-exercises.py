# Pre-render step (see _quarto.yml): rebuild exercises/exercises.qmd from the lectures,
# quizzes and problem classes by running extras/collect_exercises.jl.
# Uses the first Julia that actually starts ($JULIA, then juliaup, then `julia` on PATH).
import os, shutil, subprocess, sys

script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'collect_exercises.jl')
candidates = [os.environ.get('JULIA'), os.path.expanduser('~/.juliaup/bin/julia'), shutil.which('julia')]

for julia in filter(None, candidates):
    if not os.path.exists(julia):
        continue
    try:
        subprocess.run([julia, '--startup-file=no', '-e', '0'], check=True, capture_output=True, timeout=120)
    except Exception:
        continue
    sys.exit(subprocess.run([julia, '--startup-file=no', script]).returncode)

sys.exit('collect_exercises: no working Julia found (set $JULIA to the julia executable)')
