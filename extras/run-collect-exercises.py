# Pre-render step (see _quarto.yml): rebuild exercises/exercises.qmd from the lectures,
# quizzes and problem classes by running extras/collect_exercises.jl.
# Uses the first Julia that actually starts ($JULIA, then juliaup, then `julia` on PATH).
# Skipped (it takes several seconds, mostly Julia compiling the script) when none of its inputs
# changed since the last run; set COLLECT_EXERCISES_FORCE=1 to run it anyway.
import glob, os, shutil, subprocess, sys, time

here   = os.path.dirname(os.path.abspath(__file__))
root   = os.path.dirname(here)
script = os.path.join(here, 'collect_exercises.jl')
stamp  = os.path.join(root, '.quarto', 'collect-exercises.stamp')
output = os.path.join(root, 'exercises', 'exercises.qmd')

# everything collect_exercises.jl reads (the folders too, so that adding or removing a file counts)
dirs   = [os.path.join(root, d) for d in ('lectures', 'exercises/quizzes', 'exercises/Problem classes', 'exercises/past-papers')]
inputs = [script, __file__] + dirs + [f for d in dirs for f in glob.glob(os.path.join(d, '*'))]

def up_to_date():
    if os.environ.get('COLLECT_EXERCISES_FORCE') or not (os.path.exists(stamp) and os.path.exists(output)
                                                         and os.path.isdir(os.path.join(root, 'exercises', 'bank-media'))):
        return False
    t = os.path.getmtime(stamp)
    return all(os.path.getmtime(f) < t for f in inputs if os.path.exists(f))

if up_to_date():
    print('collect_exercises: inputs unchanged, exercises/exercises.qmd is up to date')
    sys.exit(0)

candidates = [os.environ.get('JULIA'), os.path.expanduser('~/.juliaup/bin/julia'), shutil.which('julia')]

for julia in filter(None, candidates):
    if not os.path.exists(julia):
        continue
    try:
        subprocess.run([julia, '--startup-file=no', '-e', '0'], check=True, capture_output=True, timeout=120)
    except Exception:
        continue
    start = time.time()
    code  = subprocess.run([julia, '--startup-file=no', script]).returncode
    if code == 0:   # dated to the start, so that files saved during the run count as changed next time
        os.makedirs(os.path.dirname(stamp), exist_ok=True)
        open(stamp, 'w').close()
        os.utime(stamp, (start, start))
    sys.exit(code)

sys.exit('collect_exercises: no working Julia found (set $JULIA to the julia executable)')
