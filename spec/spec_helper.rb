require File.join(File.dirname(__FILE__), '..', 'sneaker_bot.core.rb')
require 'rspec/autorun'

Bundler.require(:test)

RSpec.configure do |config|
	DataMapper.setup(:default, "sqlite::memory:")
	DataMapper.logger.set_log($stdout, :warn)
	DataMapper.auto_migrate!

	config.before(:each) do
		DataMapper.auto_migrate!
	end
end
