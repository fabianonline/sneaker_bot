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
	attr_accessor :status_changed, :current_sneak, :twitter
	def initialize
		@twitter = TwitterOAuth::Client.new(
				:consumer_key => $config[:twitter][:consumer_key],
				:consumer_secret => $config[:twitter][:consumer_secret],
				:token => $config[:twitter][:token],
				:secret => $config[:twitter][:secret]
		)
		$config[:twitter][:bot_user] = @twitter.settings['screen_name'] || $config[:twitter][:bot_user] if @twitter
		@status_changed = false
		@current_sneak = Sneak.newest
	end
	
	def get_tweets(ignore_since_id=false)
		since_id = ignore_since_id  ?  1  :  Value.get("since_id", 1)
		tweets = @twitter.mentions(:since_id=>since_id).reverse rescue nil
		puts "\n\nAchtung, keine Mentions abgerufen bekommen!" and return [] if tweets.nil?
		tweets.each do |tweet|
			since_id = tweet['id'] if tweet['id']>since_id
		end
		Value.set("since_id", since_id)
		tweets
	end

	def process_tweet(tweet)
		puts
		puts
		unless p=/^@#{$config[:twitter][:bot_user]}\b+(.+)$/i.match(tweet["text"])
			puts "#{tweet["text"]} - Nicht direkt an mich. Ignoriere."
			return
		end

		user = User.first(:twitter_id=>tweet["user"]["id"])
		user = User.first(:username=>tweet["user"]["screen_name"]) if user.nil?
		user = User.new if user.nil?
		user.twitter_id = tweet["user"]["id"]
		user.username = tweet["user"]["screen_name"]
		user.reminder_ignored = 0
		user.save
		analyze_tweet(user, p[1].strip, :time=>DateTime.parse(tweet['created_at']).new_offset(DateTime.now.offset()))
	end

	def analyze_tweet(user, text, hash={})
		time = hash[:time] || DateTime.now
		internal = hash[:internal] || false
		print text + "  -  "
		if (p=/set @?([^ ]+) (.+)$/i.match(text))
			respond_to_set(user, p[1], p[2])
		elsif(p=/sneak (.+)$/i.match(text))
			respond_to_sneak(user, p[1])
		elsif ((p=/\bbonus([+\-=])([0-9]+)/i.match(text)) && internal)
			respond_to_bonus(user, p[1], p[2])
		elsif ((p=/\balias\b(.+)/i.match(text)) && internal)
			respond_to_alias(user, p[1])
		elsif (p=/\becho\b(.+)/i.match(text))
			respond_to_echo(user, p[1])
		elsif /\breservierung\b/i.match(text)
			respond_to_reservation(user, text)
		elsif (p=/\bauto\b(.+)/i.match(text))
			respond_to_auto(user, p[1])
		elsif /\b(ja|jo|jupp|yes|jop)\b/i.match(text)
			respond_to_yes(user, text, time)
		elsif /\b(nein|nope|no)\b/i.match(text)
			respond_to_no(user, text, time)
		elsif (p=/\bbc\b(.+)/i.match(text))
			respond_to_bc(user, p[1])
		elsif /\bstatus\b/i.match(text)
			respond_to_status
		end
	end

	def respond_to_set(user, new_user, new_text)
		unless user.admin
			puts "Admin-versuch, erfolglos."
			return
		end
		puts "admin"
		user = User.first_or_create(:username=>new_user)
		analyze_tweet(user, new_text, :internal=>true)
	end
	
	def respond_to_bonus(user, sign, number)
		puts "bonus"
		case sign
			when "+" then user.bonus_points += number.to_i
			when "-" then user.bonus_points -= number.to_i
			else user.bonus_points = number
		end
		user.save or raise "Fehler beim Speichern: #{user.errors.collect(&:to_s).join("; ")}"
	end

	def respond_to_echo(user, text)
		unless user.admin
			puts "Admin-Versuch, erfolglos."
			return
		end
		tweet("#{user.to_s}: #{text}")
	end
	
	def respond_to_alias(user, new_alias)
		puts "alias"
		user.alias = new_alias.strip
		user.save or raise "Fehler beim Speichern: #{user.errors.collect(&:to_s).join("; ")}"
	end
	
	def respond_to_auto(user, text)
		puts "auto"
		user.auto = text.strip
		user.save or raise "Fehler beim Speichern: #{user.errors.collect(&:to_s).join("; ")}"
		analyze_tweet(user, text)
	end

	def respond_to_reservation(user, text)
		unless user.admin
			puts "Admin-Versuch, erfolglos."
			return
		end
		puts "reservierung"
		@current_sneak.reservations.destroy
		text.scan(/\b(\d)x(\d{4})\b/).each {|m| @current_sneak.reservations.create(:number=>m[1], :count=>m[0])}
		@status_changed = true
	end
	
	def respond_to_yes(user, text, time)
		puts "ja"
		Participation.all(:user=>user, :sneak=>@current_sneak).each {|p| p.active=false; p.save}
		p = Participation.new(:text=>text, :user=>user, :sneak=>@current_sneak, :sum=>1, :time=>time)
		if matches = /\+ *(\d+)/.match(text)
			p.sum += matches[1].to_i
		end
		
		p.psp = (/psp/i.match(text) != nil)
		p.frei = (/frei/i.match(text) != nil)
		p.save or raise "Fehler beim Speichern: #{p.errors.collect(&:to_s).join("; ")}"
		@status_changed = true
	end
	
	def respond_to_no(user, text, time)
		puts "nein"
		Participation.all(:user=>user, :sneak=>@current_sneak).each {|p| p.active=false; p.save}
		Participation.create(:text=>text, :user=>user, :sneak=>@current_sneak, :sum=>0, :time=>time)
		@status_changed = true
	end
	
	def respond_to_status
		puts "status"
		@status_changed = true
	end
	
	def respond_to_sneak(user, text)
		unless user.admin
			puts "admin-versuch, erfolglos."
			return
		end
		puts "sneak"
		if matches=/bonus_points=([0-9]+)/.match(text)
			@current_sneak.bonus_points = matches[1]
		end
		if matches=/variant=(single|double)/.match(text)
			@current_sneak.variant = matches[1]
		end
		@current_sneak.save
	end

	def respond_to_bc(user, text)
		unless user.admin
			puts "Admin-Versuch, erfolglos."
			return
		end
		puts "bc"
		text.scan(/\b(\d+)=(\d|unused)\b/).each do |match|
			card = Bonuscard.get(match[0])
			card = Bonuscard.new(:id=>match[0], :created_at_sneak=>@current_sneak[:id]-1) unless card
			if match[1].downcase=="unused"
				card.used_at_sneak = nil
				card.used_by_user.bonus_points += 5
				card.used_by_user.save
				card.used_by_user = nil
			else
				next if card.used_at_sneak!=nil
				card.points = match[1]
			end
			card.save
		end
	end
	
	def tweet_status
		prefix = "#{%w(So Mo Di Mi Do Fr Sa)[Date.today.wday]} #{Time.now.strftime("%H:%M")}: #{@current_sneak.sum}"
		prefix << "/#{@current_sneak.reservations.collect(&:count).reduce(&:+)}" if @current_sneak.reservations.count>0
		prefix << "\n"
		default_prefix = prefix
		prefix_len = prefix.length
		suffix = "\nhttp://sneaker-bot.fabianonline.de"
		suffix_len = 21 # 20 chars for the link + 1 newline character
		parts = @current_sneak.participations.all(:sum.gt=>0, :active=>true).collect(&:to_s_short).sort
		taken_parts = []
		while parts.count>0
			taken_parts.push parts.shift
			length = prefix_len + suffix_len + taken_parts.join(", ").length
			if length>135
				parts.unshift taken_parts.pop
				tweet(prefix + taken_parts.join(", ") + ", ..." + suffix)
				prefix = default_prefix + "... "
				prefix_len = prefix.length
				taken_parts = []
			end
		end
		
		tweet(prefix + taken_parts.join(", ") + suffix)
	end
	
	def give_points
		cards = @current_sneak.bonuscards
		cards.each do |card|
			if card.points==5 && !@current_sneak.double? && card.used_by_user
				card.used_by_user.bonus_points -= 5
				card.used_at_sneak = @current_sneak
				card.save
			end
			
			if card.used_by_user
				card.used_by_user.bonus_points += @current_sneak.bonus_points
				card.used_by_user.save
			end
		end

		guests = @current_sneak.participations.all(:sum.gt=>0, :active=>true).collect(&:sum).inject(&:+)
		cards = Bonuscard.all(:points.lte=>(5-@current_sneak.bonus_points), :used_by_user=>nil, :order=>[:points.desc, :id])
		guests.times do
			card = cards.shift || Bonuscard.new(:created_at_sneak=>@current_sneak) unless card
			card.points += @current_sneak.bonus_points
			card.save
		end

	end
	
	def process_auto
		User.all(:twitter_id.not=>nil, :auto.not=>nil).each {|u| analyze_tweet(u, u.auto, :internal=>true)}
	end
	
	def send_invitation
		tweet("Eine neue Sneak steht an. Anmeldung wie immer per 'ja', 'nein' oder auch 'ja +1'.")
	end
	
	def tweet(text)
		puts "TWEET: #{text.gsub("\n", "\\n")}"
		@twitter.update(text)
	end

	def sneak_reservable?
		html = open("http://dortmund-ticket.global-ticketing.com/gt/info"){|f| f.read}
		html.match(/sneak/i)!=nil
	end

	def remind_users
		User.all(:twitter_id.not=>nil, :reminder_ignored.lte=>$config[:settings][:reminder][:count]).select{|u| u.participations.all(:sneak=>@current_sneak).count==0}.each do |user|
			user.reminder_ignored+=1
			user.save
			text = "@#{user.username} #SneakTeilnahmeErinnerungsTweet. ;-)"
			if @current_sneak.double?
				text << " Anscheinend ist DoubleSneak. Anmeldeschluss ist i.d.R. Mittwoch mittag!"
			end
			tweet(text)
		end
	end
	
	def self.cron
		sb = SneakerBot.new

		unless Value.get("next_website_check_at", Time.new)>Time.now || $config[:settings][:notify_if_reservable].count==0
			if sb.sneak_reservable?
				sb.tweet("#{$config[:settings][:notify_if_reservable].join(" ")} Die Sneak ist ab *jetzt* anscheinend reservierbar. Aktuelle Anmeldungen: #{sb.current_sneak.sum}")
				Value.set("next_website_check_at", Sneak.newest.time+1)
			end
		end
		
		next_sneak = Sneak.newest.time rescue DateTime.new
		if next_sneak < DateTime.now
			sb.give_points
			Sneak.create
			sb.current_sneak = Sneak.newest
			sb.process_auto
			sb.send_invitation
		end

		next_status_time = Value.get('next_status_time', Time.new)
		if next_status_time < Time.now
			sb.status_changed = true
			Value.set('next_status_time', Chronic.parse("next #{$config[:settings][:status_time]}"))
		end

		next_reminder_time = Value.get('next_reminder_time', Time.new)
		if next_reminder_time < Time.now
			Value.set('next_reminder_time', Chronic.parse("next #{$config[:settings][:reminder][:time]}"))
			sb.remind_users
		end

		
		sb.get_tweets.each {|t| sb.process_tweet(t)}
		sb.current_sneak.update_sum
		sb.tweet_status if sb.status_changed
	end

	def self.console
		user = User.first(:admin=>true)
		sb = SneakerBot.new

		print "> "
		
		while line = STDIN.gets.chomp rescue nil
			sb.analyze_tweet(user, line, :internal=>true)
			print "> "
		end
	end
end
