-- Mutant renameCached for checks.x86_64-linux.devloop-queries (design D14):
-- a later nixbot migration renaming a column the attribute query reads,
-- applied after the fixtures, so the attribute query must fail.
ALTER TABLE build_attributes RENAME COLUMN cached TO cached_renamed;
