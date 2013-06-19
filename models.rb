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
	property :variant, String
	
	has n, :participations
	has n, :reservations
	
	def self.create(time=nil)
		time = Chronic.parse("next #{$config[:settings][:sneak_time]}") unless time
		s = Sneak.new(:time=>time)
		if time.day<=7
			s.variant = "double"
			s.bonus_points = 2
		else
			s.variant = "single"
			s.bonus_points = 1
		end
		s.save
		s
	end
	
	def self.newest
		self.first(:order=>[:time.desc]) || self.create
	end
	
	def update_sum
		self.sum = self.participations.all(:active=>true).collect(&:sum).inject(:+)
		self.save
	end
	
	def double?; variant=="double"; end

	def bonuscards
		participations = self.participations.all(:active=>true, :sum.gt=>0, :order=>:time).sort_by{|p|p.user.bonus_points}.reverse
		cards = Bonuscard.all(:used_by_user=>nil, :order=>[:points.desc, :id]).to_a
		index = 0
		participations.each_with_index do |part, index|
			cards << Bonuscard.new(:created_at_sneak=>self) unless cards[index]
			cards[index].used_by_user = part.user
		end
		cards.delete_if{|c| c.points>=5 && c.used_by_user==nil}
		guests = participations.collect{|p| p.sum-1}.inject(&:+)
		guests.times do
			index+=1
			cards << Bonuscard.new(:created_at_sneak=>self) unless cards[index]
		end

		return cards.take(index+1)
	end
end

class Reservation
	include DataMapper::Resource

	property :id, Serial
	property :number, String, :length=>4
	property :count, Integer
	belongs_to :sneak
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
	property :time, DateTime
	
	def to_s_short
		str = "#{user}"
		str << " +#{sum-1}" if sum>1
		tags = []
		tags << "B" if user.bonus_points>=5 && !sneak.double?
		tags << "P" if psp
		tags << "F" if frei
		str << " [#{tags.sort.join(',')}]" if tags.count>0
		str
	end
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

class Bonuscard
	include DataMapper::Resource

	property :id, Serial
	property :points, Integer, :default=>0
	
	belongs_to :used_by_user, :model=>'User', :required=>false
	belongs_to :used_at_sneak, :model=>'Sneak', :required=>false
	belongs_to :created_at_sneak, :model=>'Sneak', :required=>false
end
