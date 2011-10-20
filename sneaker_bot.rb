#!/usr/bin/ruby
# TODO: Gemfile

require 'rubygems'
require 'twitter_oauth'
require 'yaml'
require 'chronic'

class SneakBot
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
        end
        
        unless @data[:next_status] && @data[:next_status]>Time.now
            @data[:next_status] = Chronic.parse("next #{@config['settings']['status']['time']}")
            @status_changed = true
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
        next unless /^@sneaker_bot /.match text.downcase
        print "#{sender}: #{text} - "
        if %w(ja jo jupp yes).any? {|str| text.downcase.include? str}
            puts "ja"
            @data[:current][:members] ||= {}
            @data[:current][:members][sender] = {:text=>text, :count=>1, :extras=>[]}
            if matches = /\+ *(\d+)/.match(text)
                @data[:current][:members][sender][:count] += matches[1].to_i
            end
            @data[:current][:members][sender][:extras] << :b if /bonus/i.match(text)
            @data[:current][:members][sender][:extras] << :f if /frei/i.match(text)
            @status_changed = true
        elsif %w(nein nope no nö nicht).any? {|str| text.downcase.include? str}
            puts "nein"
            @data[:current][:members].delete sender rescue nil
            @status_changed = true
        elsif text.downcase.include? "status"
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
            string = mem[0];
            string+= "+#{mem[1][:count]-1}" if mem[1][:count]>1
            string+= " [" + mem[1][:extras].collect{|e| e.to_s.upcase}.join(",") + "]" if mem[1][:extras] && mem[1][:extras].count>0
            string
        end.join(', ')
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
end

if $0==__FILE__
    bot = SneakBot.new
    bot.check_times
    bot.process_tweets
    bot.tweet_status

    bot.save_data
end
