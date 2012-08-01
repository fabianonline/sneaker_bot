require 'rspec/core/rake_task'

desc "run specs"
RSpec::Core::RakeTask.new

desc "run rcov"
RSpec::Core::RakeTask.new(:rcov) do |t|
	t.rcov = true
	t.rcov_opts = %w(-Ispec --exclude gems/,spec/)
end

task :default=>:spec
