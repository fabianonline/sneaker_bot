#!/usr/bin/ruby
# TODO: Gemfile

require 'rubygems'
require 'twitter_oauth'
require 'yaml'
require 'chronic'

class SneakerBot
    attr_accessor :twitter, :config, :data, :status_changed
    
    def initialize
        @config = YAML.load_file(File.join(File.dirname(__FILE__), 'config.yml'))
        @status_changed = false
        @twitter = TwitterOAuth::Client.new(
                :consumer_key => @config["twitter"]["consumer_key"],
                :consumer_secret => @config["twitter"]["consumer_secret"],
                :token => @config["twitter"]["token"],
                :secret => @config["twitter"]["secret"]
        )
        @data = YAML.load_file(File.join(File.dirname(__FILE__), 'data.yml')) rescue {:current=>{:members=>{}}, :backup=>[]}
    end
    
    def check_times
        last_target = @data[:current][:target]
        unless last_target && last_target > Time.now
            reset_data
            next_target = Chronic.parse("next #{@config['settings']['reset']['day']} #{@config['settings']['reset']['time']}")
            @data[:current][:target] = next_target
            
            send_invitation
            process_tweet(:sender=>"fabianonline", :text=>"@sneaker_bot ja")
        end
        
        unless @data[:next_status] && @data[:next_status]>Time.now
            @data[:next_status] = Chronic.parse("next #{@config['settings']['status']['time']}")
            @status_changed = true
        end
        
        unless @data[:next_reminder] && @data[:next_reminder]>Time.now
            @data[:next_reminder] = Chronic.parse("next #{@config['settings']['reminder']['day']} #{@config['settings']['reminder']['time']}")
            send_reminder
        end
    end
    
    def load_tweets
        since_id = @data[:maxknownid] || 1
        mentions = begin
            @twitter.mentions(:since_id=>since_id).reverse
        rescue
            puts "Twitter machte Probleme."
            exit 1
        end
        mentions.each do |mention|
            since_id = mention['id'] if mention['id'] > since_id
            sender = mention['user']['screen_name']
            text = mention['text']
            process_tweet :sender=>sender, :text=>text
        end
        @data[:maxknownid] = since_id
        calculate_sum if @status_changed
    end
    
    def process_tweet(data={})
        text = data[:text]
        sender = data[:sender]
        print "#{sender}: #{text} - "
        unless /^@sneaker_bot /.match(text.downcase)
            puts "nicht an mich. Ignoriere..."
            return nil
        end

        if /\b(ja|jo|jupp|yes)\b/i.match(text)
            puts "ja"
            @data[:current][:members] ||= {}
            @data[:current][:members][sender] = {:text=>text, :count=>1, :extras=>[]}
            if matches = /\+ *(\d+)/.match(text)
                @data[:current][:members][sender][:count] += matches[1].to_i
            end
            @data[:current][:members][sender][:extras] << :b if /bonus/i.match(text)
            @data[:current][:members][sender][:extras] << :f if /frei/i.match(text)
            @status_changed = true
        elsif /\b(nein|nope|no|nö)\b/i.match(text)
            puts "nein"
            @data[:current][:members] ||= {}
            @data[:current][:members][sender] = {:text=>text, :count=>0, :extras=>[]}
            @status_changed = true
        elsif /\bstatus\b/i.match(text)
            puts "status"
            @status_changed = true
        else
            puts "hä?"
        end
    end
    
    def calculate_sum
        @data[:current][:sum] = @data[:current][:members].inject(0) do |sum, member|
            sum + (member[1][:count] rescue 0)
        end
    end
    
    def tweet_status
        return if @data[:current][:members].count == 0
        return unless @status_changed
        days = %w(So Mo Di Mi Do Fr Sa)
        time = "#{days[Date.today.wday]} #{Time.now.strftime('%H:%M')}"
        count = @data[:current][:sum]
        members = @data[:current][:members].collect do |mem|
            next if mem[1][:count]==0
            string = mem[0];
            string+= "+#{mem[1][:count]-1}" if mem[1][:count]>1
            string+= " [" + mem[1][:extras].collect{|e| e.to_s.upcase}.join(",") + "]" if mem[1][:extras] && mem[1][:extras].count>0
            string
        end.compact.join(', ')
        string = "#{time}: #{count}\n#{members}"
        
        @twitter.update string
        p "Twitter: #{string}"
    end
    
    def save_data
        File.open(File.join(File.dirname(__FILE__), 'data.yml'), 'w') {|f| f.write @data.to_yaml}
    end
    
    def reset_data
        @data[:backup] << @data[:current]
        @data[:current] = {:members=>{}}
    end
    
    def send_invitation
        @twitter.update('Eine neue Sneak steht an. Anmeldung per "ja" oder "ja +1", Abmeldung per "nein".')
    end
    
    def send_reminder
        old_members = @data[:backup][-2..-1].collect{|d| d[:members].keys rescue []}.flatten.uniq
        current_members = @data[:current][:members].keys rescue []
        to_remind = old_members - current_members
        to_remind.each do |receiver|
            @twitter.update "@#{receiver} Erinnerung: Du wolltest mir noch mitteilen, ob du diese Woche zur Sneak mitkommen willst... :D" rescue nil
        end
    end
end

if $0==__FILE__
    bot = SneakerBot.new
    bot.load_tweets
    bot.check_times
    bot.tweet_status

    bot.save_data
end
