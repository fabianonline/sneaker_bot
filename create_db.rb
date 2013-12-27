# run using "bundle exec ruby create_db.rb"

# This enables use of require_relative with ruby < 1.9.2
unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end

require 'data_mapper'
require_relative 'models.rb'

$config = YAML.load_file(File.join(File.dirname(__FILE__), 'config.yml'))
DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, $config[:database])

## Only if you want to delete everything first
# DataMapper.auto_migrate!

DataMapper.auto_upgrade!