package.json           the package (ES modules); `npm run check` is tools/check.py
src/                   the code; modules without side effects on import
src/counter.js         Counter: a worked example of testable logic (replace it)
tests/unit/            fast tests of plain code (the quick tier)
tests/integration/     slower tests that cross a boundary (the full tier)
