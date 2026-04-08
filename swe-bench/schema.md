FaultLocalizer
      ↓
3x CodeAnalyst (parallel) → majority vote on root cause
      ↓
PatchWriter
      ↓
TestValidator
  ├─ Step 1: try to actually apply + run the patch
  ├─ Step 2: if can't run → LLM reasons about it
  └─ PASS → done
      FAIL → send back to 3x CodeAnalyst with failure reason
              ↓
           new majority vote → new patch → validate again
           (max 3 rounds)