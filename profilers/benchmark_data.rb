require 'benchmark'
require_relative '../task-1'

def time(name, &block)
  time = Benchmark.realtime do
    block.call
  end

  puts "#{name} Completed in #{time.round(3)} ms"
end

[100_000].each do |line|
  time(line) { work("data/data_large.txt", disable_gc: true) }
end
