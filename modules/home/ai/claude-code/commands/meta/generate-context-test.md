---
argument-hint: <topic-or-guideline>
description: Generate "brown M&M" test questions to validate LLM context inclusion
---

Generate test questions that reveal whether an LLM has internalized a given topic, guideline, or instruction without directly asking about it.

## Background

Van Halen's concert rider famously required a bowl of M&Ms with all brown ones removed.
This wasn't about candy preferences - it was a test to see if venues had carefully read the entire technical rider.
If brown M&Ms were present, it indicated the venue might have skipped other critical requirements.

Similarly, these test questions probe whether context (CLAUDE.md instructions, preferences, guidelines) has been properly loaded and internalized by the model.

See Jesse Warden's [How I *Should* Code With AI](https://youtu.be/yxLB9RenpDI?t=4251) for this concept applied to AI coding workflows.

## Test Question Design Principles

Effective context tests should:

1. **Trigger application, not recitation** - Ask for output that would differ based on whether the guideline is internalized, not "what does guideline X say?"

2. **Use indirect scenarios** - Present a task where the guideline naturally applies rather than referencing it directly

3. **Have clear pass/fail signals** - A model WITH context produces observably different output than one WITHOUT

4. **Cover multiple aspects** - Generate tests for different facets of the topic

## Output Format

For the given topic, generate 3-5 test questions in order of increasing subtlety:

### Test 1: Direct trigger
A task that directly exercises the guideline without naming it.
- **Question**: [the prompt to give the LLM]
- **With context**: [expected behavior/output characteristics]
- **Without context**: [likely default behavior]
- **Key signal**: [specific phrase or pattern that reveals context presence]

### Test 2: Review/critique style
Ask the LLM to evaluate something that violates or follows the guideline.
- **Question**: [the prompt]
- **With context**: [expected critique]
- **Without context**: [likely response]
- **Key signal**: [what to look for]

### Test 3: Subtle indirect
A tangential task where the guideline would influence approach.
- **Question**: [the prompt]
- **With context**: [expected behavior]
- **Without context**: [likely default]
- **Key signal**: [differentiator]

### Test 4-5: (if applicable)
Additional tests for complex topics with multiple facets.

## Usage Notes

- Run tests in a fresh session or context to validate inclusion
- The "without context" predictions assume default Claude behavior
- Tests work best when the guideline produces meaningfully different outputs, not just stylistic variations

---

Generate brown M&M test questions for the following topic or guideline:

$ARGUMENTS
