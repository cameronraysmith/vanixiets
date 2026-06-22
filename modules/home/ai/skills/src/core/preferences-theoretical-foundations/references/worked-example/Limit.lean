/-
  Limit.lean — the idealized type system underneath `limit.py`.

  The four runtime `# STATIC-GAP:` comments of the Python file — invariants it
  can enforce only dynamically — are here promoted to *typed, machine-checked*
  structure (Lean 4 core; no Mathlib):

    STATIC GAP 1  graded modality   the grade lives IN THE TYPE:   Prog S g α
    STATIC GAP 2  dependent decide   event type DEPENDS on command: Moved r  (moveOf)
    STATIC GAP 3  exhaustiveness     evolve is total; the impossible case CANNOT be written
    STATIC GAP 4  static effect row   programs are indexed by the signature S : Sig

  What NO type system closes yet (a separate, field-level claim — do not
  conflate it with the four local gaps above): the whole trajectory runs an
  unbounded number of steps, so its grade is data-dependent, and the strongest
  type available is an EXISTENTIAL grade (`Trajectory`, §6). Pinning that
  statically would take a *conjectural synthesis* of four research lines that
  remain unintegrated — quantitative/graded type theory, multimodal type
  theory, higher-order (scoped/hefty) algebraic effects, and call-by-push-value
  / adjoint logic. The fragments are in hand; the unifying calculus is
  anticipated but unbuilt.

  NOTE: this file type-checks under `leanprover/lean4:v4.30.0-rc2` (Lean 4 core,
  no Mathlib); `lake build` is clean. The toolchain pin mirrors the Aeneas Lean
  backend's own pin, so the same spec can later feed a Rust -> Charon -> Aeneas
  round trip without a version bump.
-/

namespace Limit

/-! ## 0.  Grade — a commutative monoid in a resource semiring (in the type). -/

structure Grade where
  draws : Nat
  steps : Nat
deriving Repr, DecidableEq

instance : Add Grade := ⟨fun a b => ⟨a.draws + b.draws, a.steps + b.steps⟩⟩
instance : Zero Grade := ⟨⟨0, 0⟩⟩

@[simp] theorem Grade.zero_def : (0 : Grade) = ⟨0, 0⟩ := rfl
@[simp] theorem Grade.add_def (a b : Grade) :
    a + b = ⟨a.draws + b.draws, a.steps + b.steps⟩ := rfl

-- The monoid laws are routine Nat facts; the grade composes lawfully, which is
-- the ONLY reason tracking it in the type is sound rather than decorative.
example (a : Grade)     : (0 : Grade) + a = a               := by simp
example (a : Grade)     : a + (0 : Grade) = a               := by simp
example (a b c : Grade) : (a + b) + c = a + (b + c)         := by simp [Nat.add_assoc]

/-! ## 1.  STATIC GAP 4 — the effect ROW as a first-class signature, and its sum. -/

structure Sig where
  Op   : Type
  Ret  : Op → Type          -- the return type of each operation (its arity)
  cost : Op → Grade         -- the grade each operation contributes

-- Rows compose as the COPRODUCT of theories — `Prog (A.sum B)` is row-polymorphic
-- in the precise sense that effect systems mean by an open row.
def Sig.sum (A B : Sig) : Sig where
  Op   := A.Op ⊕ B.Op
  Ret  := fun | .inl a => A.Ret a | .inr b => B.Ret b
  cost := fun | .inl a => A.cost a | .inr b => B.cost b

/-! ## 2.  STATIC GAP 1 — the graded free monad: a program carries its grade in its type.

    `Prog S g α` is a program over signature `S`, of GRADE `g`, returning `α`.
    Each operation adds its cost to the index; `pure` adds nothing. This is the
    free side of the adjunction F ⊣ U — the DSL — with the grade tracked
    statically by construction. -/

inductive Prog (S : Sig) : Grade → Type → Type 1 where
  | pure {α} : α → Prog S 0 α
  | op   {α} {g : Grade} (o : S.Op) (k : S.Ret o → Prog S g α) :
        Prog S (S.cost o + g) α

/-- A handler discharges the row (the forgetful direction, U). It is the
    *capability interface* made concrete — NOT a monad-transformer stack. -/
structure Handler (S : Sig) where
  answer : (o : S.Op) → S.Ret o

/-- Running is parametric in the handler: the SAME `Prog` runs under ANY handler.
    Because the grade is already in the type, the runtime need NOT accumulate it —
    the bound that `limit.py` tracks dynamically is here erased before run time.
    `partial` only because a free-monad interpreter isn't structurally recursive;
    totality of `Prog` itself is what carries the guarantees. -/
partial def run {S : Sig} {α : Type} [Inhabited α] (h : Handler S) :
    {g : Grade} → Prog S g α → α
  | _, .pure a => a
  | _, .op o k => run h (k (h.answer o))

/-! ### The concrete row: one effect, `draw : () ⇒ Float`, of grade ⟨1,0⟩. -/

inductive DrawOp where | unif
deriving Repr

def draws : Sig where
  Op   := DrawOp
  Ret  := fun _ => Float
  cost := fun _ => ⟨1, 0⟩

/-- One draw. Its grade ⟨1,0⟩ is forced by the type, not asserted. -/
def draw : Prog draws ⟨1, 0⟩ Float :=
  .op DrawOp.unif (fun u => .pure u)

/-! ## 3.  STATIC GAP 2 — the move event is INDEXED by the reaction it came from.
    A `birth` command can produce ONLY `born`; a `death` ONLY `died`. The wrong
    pairing is not a runtime error — it is unrepresentable. -/

inductive Reaction where | birth | death
deriving Repr, DecidableEq, Inhabited

inductive Moved : Reaction → Type where
  | born : Moved .birth
  | died : Moved .death

/-- The dependent decision function. Its return type `Moved r` is the proof
    obligation `limit.py` could only leave as a comment: this code DOES NOT
    COMPILE if `.birth ↦ .died`. (Try it: `| .birth => .died` is a type error.) -/
def moveOf : (r : Reaction) → Moved r
  | .birth => .born
  | .death => .died

example : Moved .birth := .born      -- accepted
-- example : Moved .birth := .died   -- REJECTED BY TYPING (the gap, closed)

/-! ### State, parameters, command, and the effectful coalgebra `propose`. -/

structure State where
  n    : Nat        -- STATIC-GAP-adjacent: counts are Nat, so n ≥ 0 holds BY TYPING
  t    : Float
  area : Float
deriving Repr

structure Params where
  lam : Float       -- the Para parameter inferred in §7
  mu  : Float

structure Command where
  dt  : Float
  rxn : Reaction
deriving Repr, Inhabited

def mkCommand (s : State) (p : Params) (u1 u2 : Float) : Command :=
  let birth := p.lam
  let death := p.mu * s.n.toFloat
  let total := birth + death
  let dt    := (- Float.log (1.0 - u1)) / total      -- Exp(total) waiting time
  let rxn   := if u2 * total < birth then Reaction.birth else Reaction.death
  ⟨dt, rxn⟩

/-- The coalgebra: it unfolds the state into a command and, crucially, its TYPE
    records that doing so costs exactly two draws — grade ⟨2,0⟩, statically. -/
def propose (s : State) (p : Params) : Prog draws ⟨2, 0⟩ Command :=
  Prog.op DrawOp.unif fun u1 =>
    (Prog.op DrawOp.unif fun u2 => Prog.pure (mkCommand s p u1 u2)
      : Prog draws ⟨1, 0⟩ Command)

/-! ## 4.  STATIC GAP 3 — the algebra/evolve pair is TOTAL; no `AssertionError` exists. -/

inductive Event where
  | dwelt (dt : Float) (n : Nat)
  | moved {r : Reaction} (m : Moved r)      -- carries the dependent move
  | halted

/-- decide : the F-algebra leg (command ↦ events). The move it emits is typed by
    the command's reaction, so the produced event cannot contradict the command. -/
def decideBD (horizon : Float) (s : State) (c : Command) : List Event :=
  if s.t + c.dt ≥ horizon then
    [Event.dwelt (horizon - s.t) s.n, Event.halted]
  else
    [Event.dwelt c.dt s.n, Event.moved (moveOf c.rxn)]

/-- evolve : the structure map (fold). Exhaustive over `Event`. The `moved`
    constructor only admits `born`/`died`, so every case is covered with NO
    catch-all and NO unreachable branch — the Python `raise AssertionError` of
    `limit.py` is, here, not a line you are permitted to write. -/
def evolveBD (s : State) (e : Event) : State :=
  match e with
  | .dwelt dt n => { s with t := s.t + dt, area := s.area + n.toFloat * dt }
  | .moved .born => { s with n := s.n + 1 }
  | .moved .died => { s with n := s.n - 1 }   -- refinement: index `died` by 0<n to make pred total
  | .halted => s

/-- The Decider as the explicit algebra/coalgebra object (a lens). -/
structure Decider (Cmd Ev St : Type) where
  decide : St → Cmd → List Ev
  evolve : St → Ev → St

def bdDecider (horizon : Float) : Decider Command Event State where
  decide := decideBD horizon
  evolve := evolveBD

/-! ## 5.  Observability as a THEOREM: projection is a monoid homomorphism.

    "Observability is a lax-monoidal projection 2-cell off the committed event
    coalgebra" becomes, concretely: the read-model fold respects concatenation.
    We prove it for ANY commutative monoid — the genuinely idealized statement,
    independent of the numeric carrier. (The intended carrier is real-valued
    time; we abstract to a Nat monoid here precisely BECAUSE IEEE Float addition
    is not associative — the same reason real telemetry pipelines must pick an
    exact aggregation monoid to make sharded rollups agree.) -/

class CMonoid (M : Type) where
  e        : M
  op       : M → M → M
  op_assoc : ∀ a b c, op (op a b) c = op a (op b c)
  e_op     : ∀ a, op e a = a
  op_e     : ∀ a, op a e = a

def fmap {M} [CMonoid M] (f : Event → M) : List Event → M
  | []      => CMonoid.e
  | x :: xs => CMonoid.op (f x) (fmap f xs)

/-- The lax-monoidal law. This is the load-bearing proof of the whole file:
    observability recovered as a theorem, not a logging convention. -/
theorem fmap_hom {M} [CMonoid M] (f : Event → M) (xs ys : List Event) :
    fmap f (xs ++ ys) = CMonoid.op (fmap f xs) (fmap f ys) := by
  induction xs with
  | nil => simp [fmap, CMonoid.e_op]
  | cons x xs ih => simp [fmap, ih, CMonoid.op_assoc]

structure Summary where
  ticks : Nat
  mass  : Nat
deriving Repr

instance : CMonoid Summary where
  e        := ⟨0, 0⟩
  op a b   := ⟨a.ticks + b.ticks, a.mass + b.mass⟩
  op_assoc a b c := by cases a; cases b; cases c; simp [Nat.add_assoc]
  e_op a := by cases a; simp
  op_e a := by cases a; simp

def obs : Event → Summary
  | .dwelt _dt n => ⟨1, n⟩        -- idealized read: one tick, n units of mass
  | _            => ⟨0, 0⟩

def project : List Event → Summary := fmap obs

/-- The concrete corollary: the write-stream read model is a homomorphism. -/
theorem project_hom (xs ys : List Event) :
    project (xs ++ ys) = CMonoid.op (project xs) (project ys) :=
  fmap_hom obs xs ys

/-! ## 6.  The open frontier: the trajectory's grade is EXISTENTIAL.

    A single step has static grade ⟨2,0⟩ (`propose`). The full simulation runs
    an unbounded, data-dependent number of steps, so the strongest type any
    system can give its program is `Σ g, Prog draws g _`. This Σ is where static
    grading stops: graded modalities pin the grade only where control flow is
    statically bounded; unbounded recursion hands back ∃ g.

    Closing this in a single calculus is not a known result but a *conjectural
    synthesis*: four research lines — quantitative/graded type theory, multimodal
    type theory, higher-order (scoped/hefty) algebraic effects, and
    call-by-push-value / adjoint logic — are each a recognizable fragment of the
    calculus that would subsume them, but their integration has not been built or
    proven. The pieces are in hand; the unification is anticipated, not done. -/

abbrev Trajectory := Σ g : Grade, Prog draws g (List Event)

/-! ## 7.  It runs: a typed graded program, discharged by a handler. -/

def constHalf : Handler draws where
  answer := fun _ => (0.5 : Float)

#check @draw      -- draw    : Prog draws ⟨1, 0⟩ Float
#check @propose   -- propose : State → Params → Prog draws ⟨2, 0⟩ Command
#eval run constHalf (propose ⟨0, 0.0, 0.0⟩ ⟨4.0, 1.0⟩)   -- a Command, computed

end Limit
