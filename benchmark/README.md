# CaptainHook Performance Benchmarks

This directory contains performance benchmarks for CaptainHook's critical code paths.

## Overview

The benchmark suite measures:

- **Signature Verification**: Verifier performance across providers
- **Database Operations**: Event creation and query performance
- **Action Execution**: Registry lookups and action dispatch
- **Memory Usage**: Memory allocation and retention
- **End-to-End**: Complete webhook processing pipeline

## Running Benchmarks

### All Benchmarks

```bash
bundle exec rake benchmark:all
```

### Individual Benchmarks

```bash
bundle exec rake benchmark:signatures  # Signature verification
bundle exec rake benchmark:database    # Database operations
bundle exec rake benchmark:actions    # Action execution
bundle exec rake benchmark:memory      # Memory profiling
bundle exec rake benchmark:e2e         # End-to-end pipeline
```

### CI Mode (Save Results)

```bash
bundle exec rake benchmark:ci
```

Results are saved to `benchmark/results/TIMESTAMP_results.txt`

## Understanding Results

### Iterations Per Second (i/s)

Higher is better. Shows how many times an operation can be performed per second.

```
Calculating -------------------------------------
  Stripe Signature    15.234k (± 1.8%) i/s
```

This means ~15,234 signature verifications per second.

### Comparison Results

```
Comparison:
  Stripe:   15234.2 i/s
  Square:   14892.1 i/s - 1.02x slower
```

Shows relative performance between implementations.

### Memory Results

```
Total allocated: 2.45 MB
Total retained: 128 KB
```

- **Allocated**: Memory used during execution (includes garbage collected)
- **Retained**: Memory still held after execution

## Performance Targets

Target benchmarks for CaptainHook:

| Metric | Target | Notes |
|--------|--------|-------|
| Webhook Reception | > 1000/sec | End-to-end throughput |
| Signature Verification | > 10,000/sec | Per verifier |
| Event Creation | > 1000/sec | Including idempotency check |
| Action Lookup | > 50,000/sec | Registry performance |
| Memory per Request | < 5 MB | Allocated memory |

## Continuous Integration

Benchmarks run automatically on:
- Pull requests (when code changes)
- Pushes to main
- Manual workflow dispatch

Results are:
- Saved as artifacts (30-day retention)
- Posted as PR comments
- Used for regression detection

## Adding New Benchmarks

1. Create a new file in `benchmark/benchmarks/`:

```ruby
# benchmark/benchmarks/my_benchmark.rb
require_relative '../support/benchmark_helper'

BenchmarkHelper.run_benchmark('My Feature') do
  # Code to benchmark
end
```

2. Add to rake task in `lib/tasks/benchmark.rake`

3. Optionally add to `benchmark:all` task

## Interpreting CI Results

### Green (Good)

- Performance within expected range
- No significant regressions
- Memory usage stable

### Red (Investigation Needed)

- Significant slowdown (> 20%)
- Memory leaks detected
- Throughput below targets

## Baseline Comparison

To save current performance as baseline:

```bash
bundle exec rake benchmark:save_baseline
```

To compare against baseline:

```bash
bundle exec rake benchmark:compare
```

## Tips

### For Development

- Run individual benchmarks during optimization
- Use memory profiler to find allocations
- Compare before/after for changes

### For CI

- Benchmark results are in artifacts
- Click "Details" on benchmark check
- Download full results from artifacts

### Performance Optimization

1. Run baseline before changes
2. Make optimization
3. Run benchmarks again
4. Compare results
5. Commit if improved

## Troubleshooting

### Benchmarks Take Too Long

Reduce warmup/time in `BenchmarkHelper`:

```ruby
x.config(time: 2, warmup: 1)  # Faster but less accurate
```

### Memory Benchmarks Fail

Ensure sufficient memory available:

```bash
free -h  # Check available memory
```

### Database Errors

Reset test database:

```bash
RAILS_ENV=test bundle exec rails db:reset
```

## Resources

- [benchmark-ips gem](https://github.com/evanphx/benchmark-ips)
- [memory_profiler gem](https://github.com/SamSaffron/memory_profiler)
- [Ruby Performance Optimization](https://pragprog.com/titles/adrpo/ruby-performance-optimization/)
