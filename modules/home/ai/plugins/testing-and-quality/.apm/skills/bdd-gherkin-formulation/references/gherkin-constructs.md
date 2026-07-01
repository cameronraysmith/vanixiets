# Gherkin constructs

This reference paraphrases the Gherkin keyword reference so a formulator can reach for the right construct.
Source: cucumber's gherkin/reference page.
Every construct is illustrated on the account-ledger narrative; no reference text is reproduced verbatim.

## Feature

A `.feature` file opens with a single `Feature:` line naming a high-level capability and grouping the scenarios that belong to it.
Free-form description lines may follow the `Feature:` line; the runner ignores them, but reporting tools surface them, so they are the place to record what the feature is for.
The ledger service feature, for instance, names the capability and then describes in prose that the service threads an event store and a clock as explicit capabilities and that a rejected command persists nothing.

## Rule

`Rule:` (Gherkin v6 and later) represents one business rule and groups the scenarios that illustrate it.
It sits between `Feature` and its scenarios and gives the feature its acceptance-criteria structure.
Use it to state a rule a stakeholder would recognize, such as "A withdrawal that exceeds the balance is rejected as an overdraft", and place every example of that rule beneath it.

## Scenario and Example

`Scenario:` (synonym `Example:`) is a concrete example that illustrates a rule, expressed as a list of steps.
Aim for three to five steps: enough to establish a context, an event, and an outcome, few enough that the example keeps its expressive power.
Each scenario follows the Given–When–Then shape: `Given` establishes the initial context, `When` describes the event or action, and `Then` describes the expected observable outcome.

## Steps: Given, When, Then, And, But

`Given` puts the system into a known starting state and typically speaks of something already true, such as "an open account with balance 100"; it should avoid describing user interaction, which belongs in `When`.
`When` names the event or action, such as "50 is withdrawn" or "the account is opened through the service".
`Then` describes an expected outcome and its binding compares the actual result against an expected one; the outcome should be observable, something that comes out of the system rather than a value buried inside it.
Successive `Given` or `Then` lines read better when the second and later ones use `And` (or `But` for a contrast), and an asterisk `*` can stand in for any step keyword when the steps are really a list.
Keywords do not distinguish steps: two steps with identical trailing text collide regardless of whether one is `Given` and the other `Then`, which pushes you toward a less ambiguous domain language.

## Background

`Background:` holds `Given` steps shared by every scenario in a `Feature` or `Rule`, run before each one.
It is for genuinely incidental context that would otherwise repeat in every scenario — the ledger service feature uses it for "an empty event store" and "a clock fixed at a known instant".
Keep a `Background` short and vivid; if it sets up complicated state the reader must remember, prefer a higher-level step, and there is only one `Background` per `Feature` or `Rule`.

## Scenario Outline and Examples

`Scenario Outline:` (synonym `Scenario Template:`) runs one templated scenario once per row of an `Examples:` table, with `<>`-delimited parameters filled from the table's columns before each step is matched.
It collapses several near-identical scenarios into one template plus a table of cases.

```gherkin
Scenario Outline: Withdrawing against a balance
  Given an open account with balance <balance>
  When <amount> is withdrawn
  Then the account holds balance <remaining>

  Examples:
    | balance | amount | remaining |
    |     100 |     40 |        60 |
    |     100 |     25 |        75 |
```

An `Examples` column must carry an independently chosen expected value, not one the production path would compute; that hazard is treated in [`observable-outcome-discipline.md`](observable-outcome-discipline.md).

## Doc Strings

A `Doc String`, delimited by triple double-quotes (or triple backticks) on their own lines, passes a larger block of text to a step as its last argument.
Use it when a `Then` asserts on exact multi-line output, so the expected text is pinned precisely rather than checked loosely.
The opening delimiter may be annotated with a content type, such as a markdown or json tag, when the block's type matters.

## Data Tables

A `Data Table`, written as pipe-delimited rows beneath a step, passes a list or table of values to that step as its last argument.
It suits a step that establishes several related rows at once, such as a starting event history laid out as a table of event names and amounts.
Cell contents escape a newline as `\n`, a pipe as `\|`, and a backslash as `\\`.

## Tags

A tag is an `@`-prefixed label placed above a `Feature`, `Rule`, or scenario to group or select scenarios independently of file layout.
The ledger features tag scenarios with requirement labels such as `@req-decide-invariants` and `@req-service-roundtrip`, which lets a run select all scenarios for one requirement and gives traceability from a rule back to the requirement it discharges.
