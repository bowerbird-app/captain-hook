# frozen_string_literal: true

# Set up encryption keys before Rails loads
ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||= "m9zZmUjUUXMdeQnp5HeIAFQ3DdPImKAd"
ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||= "zMGZzfBbHG8t38g1M2RKD5AsnSzva90q"
ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||= "yBlRa4HF0NLzhKDXSpk1ruiDhccvRkM2"

namespace :benchmark do
  desc "Run all benchmarks"
  task all: :environment do
    puts "\n#{'=' * 80}"
    puts "CaptainHook Performance Benchmarks"
    puts("=" * 80)
    puts "Ruby: #{RUBY_VERSION}"
    puts "Rails: #{Rails.version}"
    puts "Time: #{Time.now}"
    puts("=" * 80)

    benchmarks = [
      "signature_verification_benchmark.rb",
      "database_operations_benchmark.rb",
      "action_execution_benchmark.rb",
      "memory_benchmark.rb",
      "end_to_end_benchmark.rb"
    ]

    gem_root = CaptainHook::Engine.root

    benchmarks.each do |file|
      puts "\nRunning #{file}..."
      load gem_root.join("benchmark", "benchmarks", file)
    rescue StandardError => e
      puts "Error running #{file}: #{e.message}"
      puts e.backtrace.first(5)
    end

    puts "\n#{'=' * 80}"
    puts "Benchmarks Complete!"
    puts("=" * 80)
  end

  desc "Run signature verification benchmark"
  task signatures: :environment do
    load CaptainHook::Engine.root.join("benchmark", "benchmarks", "signature_verification_benchmark.rb")
  end

  desc "Run database operations benchmark"
  task database: :environment do
    load CaptainHook::Engine.root.join("benchmark", "benchmarks", "database_operations_benchmark.rb")
  end

  desc "Run action execution benchmark"
  task actions: :environment do
    load CaptainHook::Engine.root.join("benchmark", "benchmarks", "action_execution_benchmark.rb")
  end

  desc "Run memory profiling benchmark"
  task memory: :environment do
    load CaptainHook::Engine.root.join("benchmark", "benchmarks", "memory_benchmark.rb")
  end

  desc "Run end-to-end benchmark"
  task e2e: :environment do
    load CaptainHook::Engine.root.join("benchmark", "benchmarks", "end_to_end_benchmark.rb")
  end

  desc "Run benchmarks and save results for CI"
  task ci: :environment do
    gem_root = CaptainHook::Engine.root
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    output_file = gem_root.join("benchmark", "results", "#{timestamp}_results.txt")

    puts "Running benchmarks and saving to #{output_file}..."

    # Create results file with header
    File.open(output_file, "w") do |f|
      f.puts "CaptainHook Benchmark Results"
      f.puts "=" * 80
      f.puts "Timestamp: #{Time.now}"
      f.puts "Ruby Version: #{RUBY_VERSION}"
      f.puts "Rails Version: #{Rails.version}"
      f.puts "Environment: #{Rails.env}"
      f.puts "=" * 80
      f.puts
    end

    # Redirect output to file
    original_stdout = $stdout
    $stdout = File.open(output_file, "a")

    begin
      Rake::Task["benchmark:all"].invoke
    ensure
      $stdout = original_stdout
    end

    puts "Benchmark results saved to: #{output_file}"
  end

  desc "Compare current performance against baseline"
  task compare: :environment do
    gem_root = CaptainHook::Engine.root
    baseline_file = gem_root.join("benchmark", "baseline.json")

    unless File.exist?(baseline_file)
      puts "No baseline found. Run 'rake benchmark:save_baseline' first."
      exit 1
    end

    puts "Comparing against baseline..."
    # TODO: Implement baseline comparison
    puts "Baseline comparison not yet implemented"
  end

  desc "Save current benchmark results as baseline"
  task save_baseline: :environment do
    gem_root = CaptainHook::Engine.root
    baseline_file = gem_root.join("benchmark", "baseline.json")
    puts "Saving baseline to #{baseline_file}..."
    # TODO: Implement baseline saving
    puts "Baseline saving not yet implemented"
  end
end
