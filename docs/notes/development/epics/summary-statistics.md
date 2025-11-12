# Summary Statistics

**Total Epics:** 7 (aligned to 6 migration phases + cleanup)

**Total Stories:** 34 stories across all epics

**Story Distribution:**
- Epic 1 (Phase 0 - Architectural Validation + Migration Pattern Rehearsal): 12 stories
- Epic 2 (Phase 1 - cinnabar): 6 stories
- Epic 3 (Phase 2 - blackphos): 5 stories
- Epic 4 (Phase 3 - rosegold): 3 stories
- Epic 5 (Phase 4 - argentum): 2 stories
- Epic 6 (Phase 5 - stibnite): 3 stories
- Epic 7 (Phase 6 - cleanup): 3 stories

**Parallelization Opportunities:**
- Within Phase 0: Stories 1.1-1.3 must be sequential (foundation), Stories 1.4-1.6 must be sequential (Hetzner), Stories 1.7-1.9 must be sequential (GCP, depends on Hetzner), Story 1.10 blocks on calendar time (1 week) but can do documentation (1.11) in parallel, Stories 1.11-1.12 must be sequential
- Within Phase 1: Stories 2.1-2.5 must be sequential, documentation in 2.6 can be concurrent with stability monitoring
- Across phases: Each phase must complete before next begins (stability gates enforce sequencing)

**Estimated Timeline:**
- Conservative: 17-19 weeks (3-4 weeks Phase 0 + 1-2 weeks per remaining phase + stability gates)
- Aggressive: 7-9 weeks (if all phases proceed smoothly without issues)
- Realistic: 13-15 weeks (accounting for some issues but not major blockers)

**Critical Success Factors:**
- Phase 0 infrastructure deployment success (Epic 1, Stories 1.5 + 1.8)
- Phase 0 GO/CONDITIONAL GO decision (Epic 1, Story 1.12)
- Cinnabar VPS stability validation (Epic 2, Story 2.6)
- Darwin patterns proven reusable (Epic 3, Story 3.5)
- Pre-migration readiness for stibnite (Epic 6, Story 6.1)
- Zero-regression validation at every phase

---

**For implementation:** Use the `create-story` workflow to generate individual story implementation plans from this epic breakdown.

