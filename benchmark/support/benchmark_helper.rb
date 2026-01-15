# frozen_string_literal: true

require "benchmark/ips"
require "memory_profiler"

module BenchmarkHelper
  # Run a performance benchmark and report iterations per second
  def self.run_benchmark(name, &block)
    puts "\n#{'=' * 80}"
    puts "Benchmark: #{name}"
    puts("=" * 80)

    Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)
      x.report(name, &block)
    end
  end

  # Run a memory profiling benchmark
  def self.memory_benchmark(name, &)
    puts "\n#{'=' * 80}"
    puts "Memory Benchmark: #{name}"
    puts("=" * 80)

    report = MemoryProfiler.report(&)

    puts "Total allocated: #{format_bytes(report.total_allocated_memsize)}"
    puts "Total retained: #{format_bytes(report.total_retained_memsize)}"
    puts "Total allocated objects: #{report.total_allocated}"
    puts "Total retained objects: #{report.total_retained}"

    report
  end

  # Run comparison benchmark between multiple implementations
  def self.compare_benchmarks(name, implementations = {})
    puts "\n#{'=' * 80}"
    puts "Comparison Benchmark: #{name}"
    puts("=" * 80)

    Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      implementations.each do |impl_name, impl_block|
        x.report(impl_name.to_s, &impl_block)
      end

      x.compare!
    end
  end

  # Format bytes into human-readable format
  def self.format_bytes(bytes)
    if bytes < 1024
      "#{bytes} B"
    elsif bytes < 1024 * 1024
      "#{(bytes / 1024.0).round(2)} KB"
    else
      "#{(bytes / (1024.0 * 1024)).round(2)} MB"
    end
  end
end
