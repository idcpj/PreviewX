# PreviewX — Performance Architecture

## 1. Targets

| Workload | Target |
|---|---:|
| 10 KB text | < 100 ms |
| 1 MB text | < 300 ms |
| 10 MB text | < 1 s |
| 100 MB log first viewport | < 2 s |
| 500 MB log first viewport | < 3 s |
| 10k archive entries | bounded and progressive |

Targets are engineering goals, not guarantees across all hardware.

## 2. Critical Path

```text
classification → provider selection → first meaningful render
```

Everything else is secondary.

## 3. Techniques

- streaming
- memory mapping where safe
- bounded reads
- lazy tree nodes
- incremental line index
- progressive rendering
- background syntax highlighting
- cache

## 4. Memory

Every provider gets a budget.

When exceeded:
- stop optional decoration;
- show partial preview;
- expose "file exceeds preview budget."

## 5. Benchmarks

Benchmarks must run on:
- clean cache
- warm cache
- Intel where supported
- Apple Silicon
- small/medium/large fixtures

## 6. Regression Rule

A provider PR that increases median preview latency by >20% must include justification and benchmark evidence.
