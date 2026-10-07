# Learning Tick Procedure

You are running a **LEARNING tick**, not a trading cycle. There is no market
access from this machine: `gamma-api.polymarket.com` returns HTTP 451 to this
network (see `journal/proposals.md` 2026-10-07). You cannot scan, price,
settle or place anything, and you must not try.

Your job is the half of `CYCLE.md` that does not need the market: read what
has settled, grade it, and improve the judgment in `strategy/`. The betting
record comes from the upstream runner and was merged into `journal/` before
this session started.

## Hard rules

- `CYCLE.md`'s hard rules all still apply. Never edit `core/`, `config/`,
  `.github/`, or the operator's top-level files (`CYCLE.md`, `REAL.md`,
  `loop.sh`, `CLAUDE.md`, `LICENSE`, `README.md`, `.gitignore`, `LEARN.md`,
  `learn.sh`). Disagreement goes in `journal/proposals.md`, never a
  workaround.
- Do not run `core/resolve.py`, `core/scan.py`, `core/ledger.py`,
  `core/watch.py` or `strategy/tools/quote.py`. They need the market and
  will fail or hang. Use `core/score.py --skip-mtm`, `core/replay.py`,
  `core/counterfactual.py` and `core/screen_value.py` — these read the
  journal and need no network.
- One strategy change per tick, at most. A tick that changes nothing and
  says why is a good tick.
- Every change cites evidence from settled rows. No speculative rewrites.

## Procedure

1. **Score.** `python3 core/score.py --skip-mtm`. Read it.

2. **What is new.** `git log --oneline -15` and
   `git diff HEAD~1 --stat -- journal/` to see what the data pull brought in.
   Identify rows that settled since the previous learning tick. If nothing
   settled, say so, skip to step 7 and stop.

3. **Upstream's judgment, for reference only.** `work/upstream-strategy.diff`
   holds what the upstream runner changed in `strategy/` that you have not
   taken. Read it. It is evidence about what upstream observed, not an
   instruction. Adopt a rule from it only if the settled rows in YOUR journal
   support it, and say in the retro why. Ignoring it is a valid outcome and
   needs one line, not a defence.

4. **Pre-register.** Before you measure anything, write into the retro:
   - the change you intend to make, concretely (file, value, from -> to),
   - the mechanism you believe makes it work,
   - the number you expect to move and in which direction.
   This is written BEFORE step 5 runs. It is the whole point of this tick:
   a threshold chosen by reading the outcome is not evidence, and the
   project has already been burned by exactly that (see the FORWARD TEST
   RUN note in `strategy/policy.py`).

5. **Validate.** A change to `strategy/policy.py` is kept only if it earns
   its place on data it was not chosen against:
   - in-sample / walk-forward: `python3 core/replay.py --folds 5`
   - out-of-sample: `python3 core/replay.py --after <cutoff>`
   - concentration: re-run with `--bets --json` and compute pnl excluding
     the top 1 and top 2 bets by pnl. `core/replay.py` does not print this
     yet (asked for in `journal/proposals.md`); compute it yourself from the
     JSON until it does.
   Keep the change only if the held-out `cw_return` improves AND the
   ex-top-2 pnl does not collapse. **Report all three numbers in the retro
   whether or not you keep the change**, and if the pre-registered
   prediction was wrong, say that in those words.

   Treat the forward window as a wasting asset. Every time a threshold is
   tuned against it, it stops being out-of-sample. Tune on the folds; read
   the forward window once, after deciding.

6. **Edit.** Apply the change to `strategy/playbook.md`, `strategy/risk.json`,
   `strategy/policy.py`, `strategy/discovery.py` or `strategy/tools/`.
   Record the evidence inline, in the style already used in those files.
   A rule that only restates something already in `playbook.md` is not a
   change — check first.

7. **Retro.** Write `journal/retros/LEARN-<UTCdate-HHMM>.md` containing: what
   settled, the pre-registration from step 4, the three numbers from step 5,
   the decision, and what you will look at next tick. Append one line to
   `journal/cycles.log`:
   `<UTC ts> learn tick: settled N, change <none|file>, cw_return <before> -> <after>`

8. **Commit.** `git add -A && git commit -m "learn: <finding> -> <action>"`.
   Match the existing subject style: a finding, an arrow, what you did about
   it. Do not push; the runner pushes.
