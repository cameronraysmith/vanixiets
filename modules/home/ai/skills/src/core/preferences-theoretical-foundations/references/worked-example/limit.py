#!/usr/bin/env -S uv run --script
"""
limit.py  —  one runnable artifact that instantiates the "limit object."

CONCRETE OBJECTIVE
------------------
Recover the posterior over the immigration rate lambda of a stochastic
immigration-death process  (  * --lambda-->  X  ,  X --mu*n--> *  )
from a single observed summary statistic, by Approximate Bayesian
Computation over an exactly-simulated (Gillespie/SSA) likelihood.

With mu = 1 the process is Poisson-stationary with mean lambda, so the
recovered posterior must concentrate near the truth — which lets the
program CHECK that it actually did inference, not theatre.

WHY THIS FILE
-------------
Every load-bearing construction appears once, doing real work, and is
labelled with the abstraction it instantiates.  Where Python can enforce an
invariant only at runtime that a richer type system would enforce statically,
the point is marked `# STATIC-GAP:` — read it as "checked dynamically here;
static in Limit.lean."  These are four concrete expressiveness gaps (graded
modalities, dependent contexts, exhaustiveness, static effect rows), not a
defect of the program.

Closing ALL of them at once in a single calculus is a separate, open matter:
it would take a conjectural synthesis of four research lines that are not yet
integrated — quantitative/graded type theory, multimodal type theory,
higher-order (scoped/hefty) algebraic effects, and call-by-push-value /
adjoint logic.  The fragments exist; the unifying calculus is anticipated but
unbuilt.  That field-level claim is distinct from the four local gaps below.
"""
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
from __future__ import annotations
import math, random, statistics
from dataclasses import dataclass, field, replace
from typing import Callable, Iterable, Iterator, Protocol, TypeVar

# ===========================================================================
# 0.  GRADE  —  a commutative monoid in a resource semiring R.
#     This is the *effect grade*: "what this computation did to the world,"
#     here measured as randomness consumed.  It composes lawfully (assoc +
#     unit) so the handler can ACCUMULATE it; that lawfulness is the only
#     reason grading is sound rather than decorative.
#     STATIC-GAP: enforced dynamically here; in Limit.lean this grade is a
#     TYPE-LEVEL index — a graded modality  <Grade> a  — checked statically.
#     Python tracks it as a runtime value, so the bound is observed, not proven.
# ===========================================================================
@dataclass(frozen=True)
class Grade:
    draws: int = 0       # uniforms consumed (the effect)
    steps: int = 0       # reactions fired   (the work)
    def __add__(self, o: "Grade") -> "Grade":          # semiring (+)
        return Grade(self.draws + o.draws, self.steps + o.steps)
UNIT = Grade()                                          # semiring 0 / monoid unit

# ===========================================================================
# 1.  EFFECT SIGNATURE  —  a capability interface, NOT a monad stack.
#     A program is a generator that YIELDS requests; a *handler* discharges
#     them.  Python generators are one-shot delimited continuations, so a
#     handler-over-a-generator is literally the algebraic-effects runner
#     (the effectful/Bluefin model) — the free side of  F -| U.
#     COEFFECT face: yielding `Draw` is the computation DEMANDING a
#     randomness capability of its context.  Same modality, opposite face.
# ===========================================================================
class Draw:  ...                       # request: a uniform in [0,1)
Effect = Draw
Eff = Iterator                         # an effectful program is Iterator[Effect] returning a value

class Handler(Protocol):               # the interface every interpreter satisfies
    grade: Grade
    def __call__(self, req: Effect) -> float: ...

def run(prog: Eff, h: Handler):
    """Discharge a free program against a handler (the forgetful direction).
    The SAME `prog` runs under ANY handler — parametricity in the interpreter
    is exactly 'the program is forall repr. Sym repr => repr a'."""
    try:
        req = next(prog)
        while True:
            req = prog.send(h(req))
    except StopIteration as stop:
        return stop.value

class Stochastic:                      # interpreter 1: real entropy; records a tape
    def __init__(self, rng: random.Random):
        self.rng, self.grade, self.tape = rng, UNIT, []
    def __call__(self, _req: Effect) -> float:
        u = self.rng.random(); self.tape.append(u)
        self.grade = self.grade + Grade(draws=1)
        return u

class Replay:                          # interpreter 2: a pure mock; replays a tape
    def __init__(self, tape: list[float]):
        self.it, self.grade = iter(tape), UNIT
        self.steps_seen = 0
    def __call__(self, _req: Effect) -> float:
        self.grade = self.grade + Grade(draws=1)
        return next(self.it)
# The natural transformation Stochastic ⇒ Replay is the THEOREM checked in §6:
# replaying a recorded tape reproduces the identical event stream.

# ===========================================================================
# 2.  DECIDER  —  the local algebra/coalgebra pair (a lens in Para(C)).
#     state ⊗ command --decide--> [event]     (F-algebra leg)
#     state ⊗ event   --evolve--> state       (the fold / structure map)
#     `params` is the Para parameter; ABC in §7 is *learning in Para(C)*,
#     i.e. inference over the parameter that indexes this morphism.
# ===========================================================================
@dataclass(frozen=True)
class Params: lam: float; mu: float                       # the Para parameter

@dataclass(frozen=True)
class State:                                              # the write model
    n: int = 0; t: float = 0.0; area: float = 0.0; done: bool = False

@dataclass(frozen=True)
class Command: dt: float; reaction: str                   # proposed transition

# events — the immutable facts; the log of these IS the source of truth
@dataclass(frozen=True)
class Dwelt: dt: float; n: int                            # spent dt holding count n
@dataclass(frozen=True)
class Born:  ...
@dataclass(frozen=True)
class Died:  ...
@dataclass(frozen=True)
class Halted: ...
Event = Dwelt | Born | Died | Halted

def decide(s: State, c: Command, horizon: float) -> list[Event]:
    # STATIC-GAP: in Limit.lean a dependent type makes this RETURN TYPE depend
    # on `c` (a birth-command cannot yield a Died).  Python erases that obligation.
    if s.t + c.dt >= horizon:
        return [Dwelt(horizon - s.t, s.n), Halted()]
    return [Dwelt(c.dt, s.n), Born() if c.reaction == "birth" else Died()]

def evolve(s: State, e: Event) -> State:                  # the fold over events
    if isinstance(e, Dwelt):  return replace(s, t=s.t + e.dt, area=s.area + e.n * e.dt)
    if isinstance(e, Born):   return replace(s, n=s.n + 1)
    if isinstance(e, Died):   return replace(s, n=s.n - 1)
    if isinstance(e, Halted): return replace(s, done=True)
    raise AssertionError("non-exhaustive")               # STATIC-GAP: a runtime guard; unreachable BY TYPING in Limit.lean

# ===========================================================================
# 3.  THE COALGEBRA  —  unfold state into an effectful stream of commands.
#     This is the effectful/coeffectful part: it DEMANDS randomness (Draw)
#     and PRODUCES the next command.  Rates are read from current state, so
#     state flows through the lens; the generator is just the wiring.
# ===========================================================================
def propose(s: State, p: Params) -> Eff:
    birth = p.lam
    death = p.mu * s.n
    total = birth + death                                # total > 0 since lam > 0
    u1: float = yield Draw()
    dt = -math.log1p(-u1) / total                        # Exp(total) waiting time
    u2: float = yield Draw()
    reaction = "birth" if u2 * total < birth else "death"
    return Command(dt, reaction)

# ===========================================================================
# 4.  THE DRIVER  —  compose coalgebra ∘ decide ∘ evolve into one trajectory,
#     emitting an EVENT-SOURCED LOG.  The log is the cofree comonad of
#     observations: the single committed stream from which BOTH the write
#     model (by fold, §2) and every read model (§5) are projections.
# ===========================================================================
def trajectory(p: Params, horizon: float, h: Handler) -> tuple[list[Event], State]:
    s, log = State(), []
    while not s.done:
        cmd = run(propose(s, p), h)                      # one effectful step
        if isinstance(h, (Stochastic, Replay)):
            h.grade = h.grade + Grade(steps=1)
        for e in decide(s, cmd, horizon):                # algebra: cmd -> events
            log.append(e)                                # append-only event store
            s = evolve(s, e)                             # fold: events -> state
    return log, s

# ===========================================================================
# 5.  READ MODEL  —  CQRS projection = a MONOID HOMOMORPHISM from the event
#     stream into a commutative monoid of summaries.  "Observability is a
#     lax-monoidal projection 2-cell off the committed coalgebra" is, in
#     code, exactly: project(xs ++ ys) == project(xs) <> project(ys).
#     That law is asserted in §6 — observability recovered as a THEOREM,
#     not a logging convention.
# ===========================================================================
@dataclass(frozen=True)
class Summary:                                            # the commutative monoid
    time: float = 0.0; integral: float = 0.0             # ∫ over the trace
    def __add__(self, o: "Summary") -> "Summary":        # ⊗ on summaries
        return Summary(self.time + o.time, self.integral + o.integral)
    @property
    def mean_count(self) -> float:                        # the observable we read out
        return self.integral / self.time if self.time else 0.0
S_UNIT = Summary()

def project(log: Iterable[Event]) -> Summary:            # the lax-monoidal functor
    acc = S_UNIT
    for e in log:
        if isinstance(e, Dwelt):
            acc = acc + Summary(time=e.dt, integral=e.n * e.dt)
    return acc

# ===========================================================================
# 6.  LAWS  —  the structure is only real if its laws hold.  These run at
#     import as cheap property checks (the "CI-enforced admit ledger" in
#     miniature: no law may be merely asserted in prose).
# ===========================================================================
def _check_laws() -> None:
    rng = random.Random(1)
    p = Params(lam=3.0, mu=1.0)
    log, s = trajectory(p, horizon=20.0, h=Stochastic(rng))

    # (a) projection is a monoid homomorphism  (observability-as-theorem)
    k = len(log) // 2
    whole, parts = project(log), project(log[:k]) + project(log[k:])
    assert math.isclose(whole.time, parts.time) and \
           math.isclose(whole.integral, parts.integral), "projection not lax-monoidal"

    # (b) the read model agrees with the write model — two projections of one
    #     stream must reconcile:  ∫n dt from §2's fold == §5's projection
    assert math.isclose(s.area, project(log).integral), "write/read divergence"

    # (c) determinism under replay  (the natural transformation Stochastic⇒Replay)
    h1 = Stochastic(random.Random(7)); log1, _ = trajectory(p, 20.0, h1)
    h2 = Replay(h1.tape);  log2, _ = trajectory(p, 20.0, h2)
    assert log1 == log2, "interpreter parametricity violated"
    # and the grade observed by both interpreters is identical:
    assert h1.grade == h2.grade, "grade not interpreter-invariant"
_check_laws()

# ===========================================================================
# 7.  THE OBJECTIVE  —  ABC posterior over the Para parameter lambda.
#     The whole stack above is the simulator; here we do the science:
#     observe one summary, then infer the rate that produced it.
# ===========================================================================
def summarize(p: Params, horizon: float, rng: random.Random) -> tuple[float, Grade]:
    h = Stochastic(rng)
    log, _ = trajectory(p, horizon, h)
    return project(log).mean_count, h.grade

def abc_posterior(observed: float, *, horizon: float, prior: tuple[float, float],
                  n_samples: int, eps: float, rng: random.Random) -> tuple[list[float], Grade]:
    lo, hi = prior
    accepted: list[float] = []
    budget = UNIT                                        # accumulate the effect grade
    while len(accepted) < n_samples:
        lam = rng.uniform(lo, hi)                        # draw from the prior over Para
        stat, g = summarize(Params(lam, mu=1.0), horizon, rng)
        budget = budget + g
        if abs(stat - observed) < eps:                  # the ABC acceptance kernel
            accepted.append(lam)
    return accepted, budget

def main() -> None:
    rng = random.Random(20260620)
    TRUE_LAM, HORIZON = 4.0, 60.0

    # Generate the single observation from ground truth.
    observed, _ = summarize(Params(TRUE_LAM, mu=1.0), HORIZON, rng)

    # Infer.
    post, budget = abc_posterior(
        observed, horizon=HORIZON, prior=(0.5, 8.0),
        n_samples=400, eps=0.30, rng=rng)

    post.sort()
    mean = statistics.fmean(post)
    lo90, hi90 = post[int(0.05 * len(post))], post[int(0.95 * len(post))]

    print(f"objective      : posterior over immigration rate  λ   (μ = 1)")
    print(f"ground truth   : λ* = {TRUE_LAM}")
    print(f"observed summ. : ⟨n⟩ = {observed:.3f}   (stationary mean ≈ λ)")
    print(f"posterior mean : λ̂  = {mean:.3f}")
    print(f"posterior 90%  : [{lo90:.3f}, {hi90:.3f}]")
    print(f"recovered      : {'YES' if lo90 <= TRUE_LAM <= hi90 else 'no'}"
          f"  (truth inside 90% credible interval)")
    print(f"effect grade   : {budget.draws} uniforms over {budget.steps} reactions")
    print(f"               : (runtime-tracked; STATIC-GAP — static in Limit.lean)")

if __name__ == "__main__":
    main()
