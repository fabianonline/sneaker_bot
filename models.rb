class User
	include DataMapper::Resource
	
	property :id, Serial
	property :twitter_id, Integer
	property :username, String
	property :alias, String
	property :auto, String
	property :bonus_points, Integer, :default=>0
	property :admin, Boolean, :default=>false
	property :reminder_ignored, Integer, :default=>0
	
	has n, :participations
	
	def to_s; self.alias || self.username; end
end

class Sneak
	include DataMapper::Resource
	
	property :id, Serial
	property :time, DateTime
	property :bonus_points, Integer
	property :sum, Integer, :default=>0
	
	has n, :participations
	
	def self.create(time=nil)
		time = Chronic.parse("next #{$config[:settings][:sneak_time]}") unless time
		s = Sneak.new(:time=>time)
		s.bonus_points = case time.day
			when 1..7 then 2
			else 1
		end
		s.save
		s
	end
	
	def self.newest
		self.first(:order=>[:time.desc])
	end
	
	def update_sum
		self.sum = self.participations.all(:active=>true).collect(&:sum).inject(:+)
		self.save
	end
end

class Participation
	include DataMapper::Resource
	
	property :id, Serial
	property :text, String, :length=>200
	property :sum, Integer
	property :active, Boolean, :default=>true
	property :frei, Boolean, :default=>false
	property :psp, Boolean, :default=>false
	belongs_to :user
	belongs_to :sneak
end

class Value
	include DataMapper::Resource
	
	property :name, String, :key=>true
	property :value, String
	
	def self.get(key, default=nil)
		YAML.load(self.first(:name=>key).value) rescue default
	end
	
	def self.set(key, new_value)
		elm = self.first_or_new(:name=>key)
		elm.value = YAML.dump(new_value)
		elm.save
	end
end
