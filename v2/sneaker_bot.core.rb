require 'rubygems'
require 'bundler'
require 'open-uri'
Bundler.require

$config = YAML.load_file(File.join(File.dirname(__FILE__), 'config.yml'))
DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, $config[:database])

require File.join(File.dirname(__FILE__), 'models.rb')

DataMapper.finalize

class SneakerBot
	attr_accessor :status_changed
	def initialize
		@twitter = TwitterOAuth::Client.new(
				:consumer_key => $config[:twitter][:consumer_key],
				:consumer_secret => $config[:twitter][:consumer_secret],
				:token => $config[:twitter][:token],
				:secret => $config[:twitter][:secret]
		)
		@status_changed = false
	end
	
	def get_tweets
		since_id = Value.get("since_id", 1)
		tweets = @twitter.mentions(:since_id=>since_id)#.reverse
		tweets.each do |tweet|
			since_id = tweet['id'] if tweet['id']>since_id
		end
		Value.set("since_id", since_id)
		tweets
	end
	
	def process_tweet(tweet)
		user = User.first(:twitter_id=>tweet["user"]["id"])
		user = User.first(:username=>tweet["user"]["screen_name"]) if user.nil?
		user = User.new if user.nil?
		user.twitter_id = tweet["user"]["id"]
		user.username = tweet["user"]["screen_name"]
		# don't save yet. analyze_tweet will do that, if the tweet was okay
		# This is to prevent spam bots from being added to the Users table.
		
		analyze_tweet(:user=>user, :text=>tweet["text"])
	end
		
	def analyze_tweet(hash={})
		text = hash[:text]
		print text + "  -  "
		unless /^@sneaker_bot\b/i.match(text) || hash[:internal]
			puts "Nicht direkt an mich. Ignorieren..."
			return
		end

		hash[:user].save
		
		if (p=/set @?([^ ]+) (.+)$/i.match(text))
			unless hash[:user].admin
				puts "admin-versuch, erfolglos."
				return
			end
			puts "admin"
			user = User.first_or_create(:username=>p[1])
			analyze_tweet(:text=>"#{p[2]}", :user=>user, :internal=>true)
		elsif (p=/\bauto\b(.+)/i.match(text))
			puts "auto"
			hash[:user].auto = p[1].strip
			hash[:user].save
		elsif /\b(ja|jo|jupp|yes|jop)\b/i.match(text)
			puts "ja"
			Participation.all(:user=>hash[:user], :sneak=>Sneak.newest).each {|p| p.active=false; p.save}
			p = Participation.new(:text=>text, :user=>hash[:user], :sneak=>Sneak.newest, :sum=>1)
			if matches = /\+ *(\d+)/.match(text)
				p.sum += matches[1].to_i
			end
			
			p.psp = (/psp/i.match(text) != nil)
			p.frei = (/frei/i.match(text) != nil)
			p.save
			@status_changed = true
		elsif /\b(nein|nope|no|nö)\b/i.match(text)
			puts "nein"
			Participation.all(:user=>hash[:user], :sneak=>Sneak.newest).each {|p| p.active=false; p.save}
			Participation.create(:text=>text, :user=>hash[:user], :sneak=>Sneak.newest, :sum=>0)
			@status_changed = true
		elsif /\bstatus\b/i.match(text)
			puts "status"
			@status_changed = true
		end
	end
	
	def tweet_status
		text = "#{%w(Mo Di Mi Do Fr Sa So)[Date.today.wday]} #{Time.now.strftime("%H:%M")}: #{Sneak.newest.sum}\n"
		text += Sneak.newest.participations.all(:sum.gt=>0, :active=>true).collect do |part|
			str = "#{part.user.alias || part.user.username}"
			str << " +#{part.sum-1}" if part.sum>1
			tags = []
			tags << "B" if part.user.bonus_points>=5 && Sneak.newest.time.day<=7
			tags << "P" if part.psp
			tags << "F" if part.frei
			str << " [#{tags.join(',')}]" if tags.count>0
			str
		end.sort.join(", ")
		tweet(text)
	end
	
	def give_points
		Sneak.newest.participations.all(:sum.gt=>0, :active=>true).each do |p|
			p.user.bonus_points = p.user.bonus_points % 5 unless p.sneak.time.day<=7 || p.frei
			p.user.bonus_points += p.sneak.bonus_points
			p.user.save
		end rescue nil
	end
	
	def process_auto
		User.all(:twitter_id.not=>nil, :auto.not=>nil).each {|u| analyze_tweet(:text=>u.auto, :user=>u, :internal=>true)}
	end
	
	def send_invitation
		tweet("Eine neue Sneak steht an. Anmeldung wie immer per 'ja', 'nein' oder auch 'ja +1'.")
	end
	
	def tweet(text)
		puts "TWEET: #{text}"
	end

	def sneak_reservable?
		html = open("http://dortmund-ticket.global-ticketing.com/gt/info"){|f| f.read}
		html.match(/sneak/i)!=nil
	end
	
	def self.cron
		sb = SneakerBot.new

		unless Value.get("next_website_check_at", Time.new)>Time.now
			if sb.sneak_reservable?
				sb.tweet("@fabianonline Die Sneak ist ab *jetzt* anscheinend reservierbar.")
				Value.set("next_website_check_at", Sneak.newest.time+1)
			end
		end
		
		next_sneak = Sneak.newest.time rescue DateTime.new
		if next_sneak < DateTime.now
			sb.give_points
			Sneak.create
			sb.process_auto
			sb.send_invitation
		end

		next_status_time = Value.get('next_status_time', Time.new)
		if next_status_time < Time.now
			sb.status_changed = true
			Value.set('next_status_time', Chronic.parse("next #{$config[:settings][:status_time]}"))
		end
		
		sb.get_tweets.each {|t| sb.process_tweet(t)}
		Sneak.newest.update_sum
		sb.tweet_status if sb.status_changed

		puts
		puts
		puts
	end
end
