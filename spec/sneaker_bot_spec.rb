require File.dirname(__FILE__) + '/spec_helper'

describe SneakerBot do
	before do
		@sb = SneakerBot.new
		@sb.stub!(:puts)
		@sb.stub!(:print)
		@sb.twitter.stub!(:update)
		@user = User.create(:username=>"hz", :twitter_id=>"1234", :alias=>"Heinz", :id=>42, :reminder_ignored=>0, :bonus_points=>3)
		@user_2 = User.create(:username=>"user 2", :twitter_id=>nil, :alias=>"User 2", :id=>43, :reminder_ignored=>0, :bonus_points=>0, :admin=>true)
	end

	describe "#initialize" do
		it "sets @current_sneak to the newest Sneak" do
			@sb.current_sneak.should == Sneak.newest
		end
	end

	describe "#get_tweets" do
		describe "called without parameters" do
			describe "with set since_id" do
				it "calls the twitter-API with since_id=1234" do
					Value.set("since_id", "1234")
					@sb.twitter.should_receive(:mentions).with({:since_id=>"1234"}).and_return([])
					@sb.get_tweets
				end
			end

			describe "without set since_id" do
				it "calls the twitter-API with since_id=1" do
					@sb.twitter.should_receive(:mentions).with({:since_id=>1}).and_return([])
					@sb.get_tweets
				end
			end
		end

		describe "called with ignore_since_id=true" do
			describe "with set since_id" do
				it "ignores since_id" do
					Value.set("since_id", "1234")
					@sb.twitter.should_receive(:mentions).with({:since_id=>1}).and_return([])
					@sb.get_tweets(true)
				end
			end
		end
	end

	describe "#process_tweet" do
		before do
			@tweet = {"user"=>{"id"=>"1234", "screen_name"=>"hz"}, "text"=>"@sneaker_bot ja", "created_at"=>"Wed May 30 11:31:05 +0000 2012"}
		end

		describe "with a tweet not sent directly to the bot" do
			before do
				@tweet["text"] = "@blubb @sneaker_bot ja"
			end

			it "doesn't create a new user" do
				lambda {
					@sb.process_tweet(@tweet)
				}.should_not change(User, :count)
			end

			it "doesn't call #analyze_tweet" do
				@sb.should_not_receive(:analyze_tweet)
			end
		end

		describe "with a user with matching twitter_id" do
			describe "updates the user" do
				before do
					@user.reminder_ignored = 5
					@user.username = "heinz-old"
					@user.save
					@sb.process_tweet(@tweet)
					@user.reload
				end

				it("sets the username") { @user.username.should == "hz" }
				it("resets reminder_ignored") { @user.reminder_ignored.should == 0 }
			end

			it "calls #analyze_tweet" do
				@sb.should_receive(:analyze_tweet) { |user, text, hash|
					user.should be_an(User)
					user.id.should == @user.id
					text.should == "@sneaker_bot ja"
					hash[:time].should be_a(DateTime)
				}
				@sb.process_tweet(@tweet)
			end
		end

		describe "with a user with matching username" do
			before do
				@user.reminder_ignored = 5
				@user.username = "hz"
				@user.twitter_id = nil
				@user.save
			end

			describe "updates the user" do
				before do
					@sb.process_tweet(@tweet)
					@user.reload
				end

				it("sets the twitter ID") { @user.twitter_id.should == 1234 }
				it("resets reminder_ignored") { @user.reminder_ignored.should == 0 }
			end

			it("uses the updated user") do
				@sb.should_receive(:analyze_tweet) {|user, text, hash| user.id.should == 42}
				@sb.process_tweet(@tweet)
			end
		end

		describe "with a new user" do
			before do
				@user.destroy
			end

			it "creates a new user" do
				lambda {
					@sb.process_tweet(@tweet)
				}.should change(User, :count)
			end

			describe "with attributes" do
				before do
					@sb.process_tweet(@tweet)
					@user = User.last
				end

				it("has twitter_id") { @user.twitter_id.should == 1234 }
				it("has username") { @user.username.should == "hz" }
				it("has reminder_ignored") { @user.reminder_ignored.should == 0 }
				it("is not admin") { @user.admin.should be_false }
			end
		end
	end

	describe "#analyze_tweet" do
		describe "processing 'set'-Tweets" do
			specify "text with username beginning with @" do
				@sb.should_receive(:respond_to_set).with(@user, "blubb", "neuer status")
				@sb.analyze_tweet(@user, "set @blubb neuer status")
			end
			
			specify "text with username not beginning with @" do
				@sb.should_receive(:respond_to_set).with(@user, "blubb", "neuer status")
				@sb.analyze_tweet(@user, "set blubb neuer status")
			end
		end
		
		describe "processing 'bonus'-Tweets" do
			describe "calls #respond_to_bonus" do
				specify "if called internally" do
					@sb.should_receive(:respond_to_bonus)
					@sb.analyze_tweet(@user, "bonus+1", :internal=>true)
				end
			
				specify "not if not called internally" do
					@sb.should_not_receive(:respond_to_bonus)
					@sb.analyze_tweet(@user, "bonus+1")
				end
			end
			
			describe "with sign='+'" do
				it "calls respond_to_bonus" do
					@sb.should_receive(:respond_to_bonus).with(@user, "+", "1")
					@sb.analyze_tweet(@user, "bonus+1", :internal=>true)
				end
			end
			
			describe "with sign='-'" do
				it "calls respond_to_bonus" do
					@sb.should_receive(:respond_to_bonus).with(@user, "-", "2")
					@sb.analyze_tweet(@user, "bonus-2", :internal=>true)
				end
			end
			
			describe "with sign='='" do
				it "calls respond_to_bonus" do
					@sb.should_receive(:respond_to_bonus).with(@user, "=", "12")
					@sb.analyze_tweet(@user, "bonus=12", :internal=>true)
				end
			end
		end
		
		describe "processing 'alias'-Tweets" do
			describe "calls #respond_to_alias" do
				specify "if called internally" do
					@sb.should_receive(:respond_to_alias)
					@sb.analyze_tweet(@user, "alias laborfee", :internal=>true)
				end
			
				specify "not if not called internally" do
					@sb.should_not_receive(:respond_to_alias)
					@sb.analyze_tweet(@user, "alias laborfee")
				end
			end
			
			it "calls #respond_to_alias with correct parameters" do
				@sb.should_receive(:respond_to_alias).with(@user, " laborfee")
				@sb.analyze_tweet(@user, "alias laborfee", :internal=>true)
			end
			
			it "calls #respond_to_alias even with longer aliases" do
				@sb.should_receive(:respond_to_alias).with(@user, " Laborfee, Die")
				@sb.analyze_tweet(@user, "alias Laborfee, Die", :internal=>true)
			end
		end
		
		describe "processing 'auto'-Tweets" do
			it "calls #respond_to_auto" do
				@sb.should_receive(:respond_to_auto).with(@user, " ja psp")
				@sb.analyze_tweet(@user, "auto ja psp")
			end
		end
		
		describe "processing 'ja'-Tweets" do
			it "calls #respond_to_yes" do
				@sb.should_receive(:respond_to_yes).with(@user, "ja", kind_of(DateTime))
				@sb.analyze_tweet(@user, "ja")
			end
			
			it "gives the whole string to #respond_to_yes" do
				@sb.should_receive(:respond_to_yes).with(@user, "ja +2 psp", kind_of(DateTime))
				@sb.analyze_tweet(@user, "ja +2 psp")
			end
			
			describe "reacts on tweets containing" do
				before do
					@sb.should_receive(:respond_to_yes)
				end
				
				specify("ja") { @sb.analyze_tweet(@user, "ja") }
				specify("jupp") { @sb.analyze_tweet(@user, "jupp") }
				specify("jo") { @sb.analyze_tweet(@user, "jo") }
				specify("yes psp") { @sb.analyze_tweet(@user, "yes psp") }
				specify("jop +2") { @sb.analyze_tweet(@user, "jop +2") }
			end
		end
		
		describe "processing 'nein'-Tweets" do
			it "calls #respond_to_no" do
				@sb.should_receive(:respond_to_no).with(@user, "nein", kind_of(DateTime))
				@sb.analyze_tweet(@user, "nein")
			end
			
			it "gives the whole string to #respond_to_nein" do
				@sb.should_receive(:respond_to_no).with(@user, "nein, heute nicht", kind_of(DateTime))
				@sb.analyze_tweet(@user, "nein, heute nicht")
			end
			
			describe "reacts on tweets containing" do
				before do
					@sb.should_receive(:respond_to_no)
				end
				
				specify("nein") { @sb.analyze_tweet(@user, "nein") }
				specify("nope") { @sb.analyze_tweet(@user, "nope") }
				specify("no") { @sb.analyze_tweet(@user, "no") }
			end
		end
		
		describe "processing 'status'-Tweets" do
			it "calls #respond_to_status" do
				@sb.should_receive(:respond_to_status)
				@sb.analyze_tweet(@user, "status")
			end
		end
		
		describe "processing 'sneak'-Tweets" do
			it "calls #respond_to_sneak" do
				@sb.should_receive(:respond_to_sneak)
				@sb.analyze_tweet(@user, "sneak bonus_points=1 variant=double")
			end
		end
	end

	describe "#respond_to_set" do
		describe "as non-admin" do
			it "doesn't re-analyze the tweet" do
				@sb.should_not_receive(:analyze_tweet)
				@sb.respond_to_set(@user, "user", "blubb")
			end
		end

		describe "as admin" do
			before {@user.admin = true; @user.save}

			it "creates a new user if the user is unknown" do
				expect { @sb.respond_to_set(@user, "user", "blubb") }.to change(User, :count)
			end

			it "re-analyzes the tweet" do
				@sb.should_receive(:analyze_tweet) do |user, text, hash|
					text.should == "blubb"
					user.should be_a(User)
					user.username.should == "user"
					user.twitter_id.should be_nil
				end
				@sb.respond_to_set(@user, "user", "blubb")
			end
		end
	end
	
	describe "#respond_to_bonus" do
		context "with sign='='" do
			it "sets the new value" do
				expect { @sb.respond_to_bonus(@user, "=", "4") }.to change(@user, :bonus_points).to(4)
			end
		end
		
		context "with sign='+'" do
			it "adds the value" do
				expect { @sb.respond_to_bonus(@user, "+", "2") }.to change(@user, :bonus_points).by(+2)
			end
		end
		
		context "with sign='-'" do
			it "substracts the value" do
				expect { @sb.respond_to_bonus(@user, "-", "1") }.to change(@user, :bonus_points).by(-1)
			end
		end
	end
	
	describe "#respond_to_alias" do
		it "changes the alias" do
			lambda { @sb.respond_to_alias(@user, "new_alias") }.should change(@user, :alias).to("new_alias")
		end
		
		it "strips the new alias" do
			lambda { @sb.respond_to_alias(@user, "  alias  ") }.should change(@user, :alias).to("alias")
		end
	end
	
	describe "#respond_to_reservation" do
		before { @user.admin=true; @user.save }
		
		it "adds a new reservation" do
			lambda { @sb.respond_to_reservation(@user, "4x1234") }.should change(Reservation, :count)
		end
		
		it "sets the values of the new reservation correctly" do
			@sb.respond_to_reservation(@user, "4x1234")
			Reservation.last.number.should == "1234"
			Reservation.last.count.should == 4
		end
		
		it "deletes the old reservation" do
			r = @sb.current_sneak.reservations.create(:number=>"1111", :count=>"1")
			id = r.id
			lambda { @sb.respond_to_reservation(@user, "3x3333") }.should_not change(Reservation, :count)
			Reservation.get(id).should be_nil
		end
		
		it "works with multiple reservations" do
			lambda { @sb.respond_to_reservation(@user, "1x1111, 2x2222 3x3333")}.should change(Reservation, :count).by(3)
			res = Reservation.last(3)
			res[2].number.should=="1111"
			res[2].count.should==1
			res[1].number.should=="2222"
			res[1].count.should==2
			res[0].number.should=="3333"
			res[0].count.should==3
		end
	end

	describe "#respond_to_auto" do
		it "changes user's auto value" do
			lambda { @sb.respond_to_auto(@user, "ja psp") }.should change(@user, :auto).to("ja psp")
		end
		
		it "strips the new value" do
			lambda { @sb.respond_to_auto(@user, "  ja psp  ") }.should change(@user, :auto).to("ja psp")
		end
	end
	
	describe "#respond_to_yes" do
		context "with already existing Participations" do
			before do
				Participation.create(:id=>1, :user=>@user, :sneak=>@sb.current_sneak, :text=>"ja", :sum=>1, :time=>DateTime.now, :active=>false)
				Participation.create(:id=>2, :user=>@user_2, :sneak=>@sb.current_sneak, :text=>"ja", :sum=>1, :time=>DateTime.now, :active=>true)
				Participation.create(:id=>3, :user=>@user, :sneak=>@sb.current_sneak, :text=>"ja", :sum=>1, :time=>DateTime.now, :active=>true)
			end
			
			it "doesn't change the user's previous participations" do
				lambda { @sb.respond_to_yes(@user, "ja wirklich", DateTime.now) }.should_not change{ Participation.get(1).active }
			end
			
			it "doesn't change other users' participations" do
				lambda { @sb.respond_to_yes(@user, "ja wirklich", DateTime.now) }.should_not change{ Participation.get(2).active }
			end
			
			it "changes the user's current participation's active to false" do
				lambda { @sb.respond_to_yes(@user, "ja wirklich", DateTime.now) }.should change{ Participation.get(3).active }.to(false)
			end
		end
		
		it "adds a new participation" do
			lambda { @sb.respond_to_yes(@user, "ja", DateTime.now) }.should change(Participation, :count).by(1)
		end
		
		describe "sets correct values for the new participation" do
			before do
				@sb.respond_to_yes(@user, "ja", DateTime.now)
				@participation = Participation.last
			end
			
			subject { @participation }
			
			its(:user) { should == @user }
			its(:sneak) { should == @sb.current_sneak }
			its(:text) { should == "ja" }
			its(:sum) { should == 1 }
			its(:time) { should be_a DateTime }
			its(:active) { should be_true }
			its(:psp) { should be_false }
			its(:frei) { should be_false }
		end
		
		describe "with guests" do
			it "recognizes them with space" do
				@sb.respond_to_yes(@user, "ja + 2", DateTime.now)
				Participation.last.sum.should == 3
			end
			
			it "recognizes them without space" do
				@sb.respond_to_yes(@user, "ja+1", DateTime.now)
				Participation.last.sum.should == 2
			end
		end
		
		describe "#respond_to_no" do
			context "with already existing Participations" do
				before do
					Participation.create(:id=>1, :user=>@user, :sneak=>@sb.current_sneak, :text=>"ja", :sum=>1, :time=>DateTime.now, :active=>false)
					Participation.create(:id=>2, :user=>@user_2, :sneak=>@sb.current_sneak, :text=>"ja", :sum=>1, :time=>DateTime.now, :active=>true)
					Participation.create(:id=>3, :user=>@user, :sneak=>@sb.current_sneak, :text=>"ja", :sum=>1, :time=>DateTime.now, :active=>true)
				end

				it "doesn't change the user's previous participations" do
					lambda { @sb.respond_to_no(@user, "nein", DateTime.now) }.should_not change{ Participation.get(1).active }
				end

				it "doesn't change other users' participations" do
					lambda { @sb.respond_to_no(@user, "nein", DateTime.now) }.should_not change{ Participation.get(2).active }
				end

				it "changes the user's current participation's active to false" do
					lambda { @sb.respond_to_no(@user, "nein", DateTime.now) }.should change{ Participation.get(3).active }.to(false)
				end
			end

			it "adds a new participation" do
				lambda { @sb.respond_to_no(@user, "nein", DateTime.now) }.should change(Participation, :count).by(1)
			end

			describe "sets correct values for the new participation" do
				before do
					@sb.respond_to_no(@user, "nein", DateTime.now)
					@participation = Participation.last
				end

				subject { @participation }

				its(:user) { should == @user }
				its(:sneak) { should == @sb.current_sneak }
				its(:text) { should == "nein" }
				its(:sum) { should == 0 }
				its(:time) { should be_a DateTime }
				its(:active) { should be_true }
				its(:psp) { should be_false }
				its(:frei) { should be_false }
			end

			describe "with guests" do
				it "ignores them" do
					@sb.respond_to_no(@user, "nein + 2", DateTime.now)
					Participation.last.sum.should == 0
				end
			end
		end
		
		describe "with psp" do
			it "ignores it" do
				@sb.respond_to_no(@user, "nein psp", DateTime.now)
				Participation.last.psp.should be_false
			end
		end
		
		describe "with free ticket" do
			it "ignores it" do
				@sb.respond_to_no(@user, "nein frei", DateTime.now)
				Participation.last.frei.should be_false
			end
		end
		
		it "changes @status_changed" do
			expect { @sb.respond_to_yes(@user, "ja", DateTime.now) }.to change(@sb, :status_changed).from(false).to(true)
		end
	end
	
	describe "#respond_to_status" do
		it "changes @status_changed" do
			expect {@sb.respond_to_status}.to change(@sb, :status_changed).from(false).to(true)
		end
	end
	
	describe "#respond_to_sneak" do
		
		
		it "doesn't change anything for non-admin-users" do
			expect {@sb.respond_to_sneak(@user, "bonus_points=17 variant=double")}.to_not change{@sb.current_sneak.bonus_points}
			expect {@sb.respond_to_sneak(@user, "bonus_points=17 variant=double")}.to_not change{@sb.current_sneak.variant}
		end
		
		context "from a single sneak" do
			before do
				@sb.current_sneak.variant="single"
				@sb.current_sneak.bonus_points=1
			end
			
			it "changes the variant" do
				expect {@sb.respond_to_sneak(@user_2, "variant=double")}.to change{@sb.current_sneak.variant}.from("single").to("double")
			end
		
			it "changes the bonus_points" do
				expect {@sb.respond_to_sneak(@user_2, "bonus_points=2")}.to change{@sb.current_sneak.bonus_points}.from(1).to(2)
			end
		end
		
		context "from a double sneak" do
			before do
				@sb.current_sneak.variant="double"
				@sb.current_sneak.bonus_points=2
			end
			
			it "changes the variant" do
				expect {@sb.respond_to_sneak(@user_2, "variant=single")}.to change{@sb.current_sneak.variant}.from("double").to("single")
			end
		
			it "changes the bonus_points" do
				expect {@sb.respond_to_sneak(@user_2, "bonus_points=1")}.to change{@sb.current_sneak.bonus_points}.from(2).to(1)
			end
		end
	end
	
	pending "#remind_users"

	describe "#tweet_status" do
		before do
			u1 = User.create(:username=>"Heinz mit einem sehr sehr langen Namen", :bonus_points=>3)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u1, :sum=>1, :text=>"ja", :active=>false)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u1, :sum=>2, :text=>"ja +1", :active=>true)
			u2 = User.create(:username=>"Peter der einen noch längeren Namen hat", :bonus_points=>4)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u2, :sum=>1, :text=>"ja PSP", :active=>true)
			u3 = User.create(:username=>"Horst dessen Name nicht so lang ist", :bonus_points=>1)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u3, :sum=>1, :text=>"ja", :active=>true)
			Reservation.create(:sneak=>@sb.current_sneak, :number=>"1234", :count=>1)
			Reservation.create(:sneak=>@sb.current_sneak, :number=>"5678", :count=>7)
			@sb.current_sneak.update_sum
		end
		
		it "starts with the date" do
			Time.should_receive(:now).any_number_of_times.and_return(Time.mktime(2012, 05, 03, 18, 00))
			@sb.should_receive(:tweet).once.ordered {|text| text.should match /^Do 18:00:/}
			@sb.should_receive(:tweet).any_number_of_times.ordered
			@sb.tweet_status
		end
		
		it "contains the sum and the number of reservations when given" do
			@sb.should_receive(:tweet).once.ordered {|text| text.should match /: 4\/8\n/}
			@sb.should_receive(:tweet).any_number_of_times.ordered
			@sb.tweet_status
		end
		
		it "contains the sum but not the number of reservations when they're not given" do
			Reservation.all.destroy
			@sb.should_receive(:tweet).once.ordered {|text| text.should match /: 4\n/}
			@sb.should_receive(:tweet).any_number_of_times.ordered
			@sb.tweet_status
		end

		it "sends tweets no longer than 140 chars" do
			@sb.should_receive(:tweet).any_number_of_times {|text| text.length.should < 154 }
			@sb.tweet_status
		end

		it "splits long tweets" do
			@sb.should_receive(:tweet).once.ordered {|text| text.should match(/Heinz.+Horst.+\.\.\./) }
			@sb.should_receive(:tweet).once.ordered {|text| text.should match(/^... Peter/) }
			@sb.tweet_status
		end

		it "doesn't shorten strings if they are short enough" do
			Participation.last.destroy
			@sb.should_receive(:tweet).once {|text| text.should_not match(/\.\.\./) }
			@sb.tweet_status
		end
	end

	describe "#give_points" do
		before do
			u = User.create(:id=>11, :username=>"Heinz", :bonus_points=>3)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u, :sum=>1, :text=>"ja", :active=>false)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u, :sum=>2, :text=>"ja +1", :active=>true)
			u = User.create(:id=>12, :username=>"Peter", :bonus_points=>4)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u, :sum=>1, :text=>"ja PSP", :active=>true)
			u = User.create(:id=>13, :username=>"Ansgard", :bonus_points=>5)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u, :sum=>1, :text=>"ja PSP", :active=>true)
			u = User.create(:id=>14, :username=>"Horst", :bonus_points=>5)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u, :sum=>1, :text=>"ja PSP", :active=>true, :frei=>true)
			u = User.create(:id=>15, :username=>"Paul", :bonus_points=>6)
			Participation.create(:sneak=>@sb.current_sneak, :user=>u, :sum=>1, :text=>"ja PSP", :active=>true)
		end
		
		context "after a normal sneak" do
			before { @sb.current_sneak.stub!(:double?) { false }; @sb.current_sneak.bonus_points=1; @sb.give_points}
			specify "add 1 bonus_point for people having less than 5 points" do
				User.get(11).bonus_points.should == 4
				User.get(12).bonus_points.should == 5
			end
			
			specify "assume everyone with 5 bonus_points used them to gain free entry" do
				User.get(13).bonus_points.should == 1
			end
			
			specify "users with free entry cards don't use their bonus_points but get new ones" do
				User.get(14).bonus_points.should == 6
			end
			
			specify "users with loads of points don't lose them" do
				User.get(15).bonus_points.should == 2
			end
		end
		
		context "after a double sneak" do
			before { @sb.current_sneak.stub!(:double?) { true }; @sb.current_sneak.bonus_points=2; @sb.give_points}
			specify "everyone gets two points but can't use them" do
				User.get(11).bonus_points.should == 5
				User.get(12).bonus_points.should == 6
				User.get(13).bonus_points.should == 7
				User.get(14).bonus_points.should == 7
				User.get(15).bonus_points.should == 8
			end
		end
	end

	pending "#process_auto"

	describe "#send_invitation" do
		it "sends a tweet" do
			@sb.should_receive(:tweet)
			@sb.send_invitation
		end
	end

	describe "#tweet" do
		it "calls the twitter api" do
			@sb.twitter.should_receive(:update).with("test")
			@sb.tweet("test")
		end
	end

	describe "#sneak_reservable?" do
		let(:read) { mock 'open' }
		
		it "returns true if 'sneak' is contained in the HTTP response" do
			@sb.should_receive(:open).and_return("lots of html. oh, and a sneak")
			@sb.sneak_reservable?.should be_true
		end
		
		it "returns false if 'sneak' is not contained in the HTTP response" do
			@sb.should_receive(:open).and_return("lots of html. only boring stuff.")
			@sb.sneak_reservable?.should be_false
		end
	end

	describe ".cron" do
		before do
			SneakerBot.stub!(:new) { @sb }
			@sb.stub!(:sneak_reservable?) { false }
			@sb.stub!(:get_tweets) { [] }
			@sb.stub!(:status_changed) { false }
			Value.set("next_reminder_time", Time.now+100)
		end
		
		it("should create a new instance of SneakerBot") { SneakerBot.should_receive(:new).and_return(@sb) }
		
		describe "checks the website for reservable sneaks" do
			describe "if the next check is sheduled to be in the future" do
				before { Value.set("next_website_check_at", Time.now+100) }
				
				it("doesn't call #sneak_reservable?") { @sb.should_not_receive(:sneak_reservable) }
			end
			
			describe "if the next check is sheduled to be in the past" do
				before { Value.set("next_website_check_at", Time.now-100) }
				
				it("calls #sneak_reservable?") { @sb.should_receive(:sneak_reservable?) }
				
				describe "if the sneak *is* reservable" do
					before { @sb.stub!(:sneak_reservable?) { true } }
					it("sends a tweet") { @sb.should_receive(:tweet).and_return(true) }
					it("updates next_website_check_at") { lambda{SneakerBot.cron}.should change{Value.get("next_website_check_at")} }
				end
				
				describe "if the sneak is *not* reservable" do
					before { @sb.stub!(:sneak_reservable?) { false } }
					it("doesn't send a tweet") { @sb.should_not_receive(:tweet) }
					it("doesn't update next_website_check_at") { lambda{SneakerBot.cron}.should_not change{Value.get("next_website_check_at")} }
				end
			end
		end
		
		pending "creates a new sneak"
		pending "automatically sends status tweets"
		pending "automatically sends reminder tweets"
		pending "processes tweets"
		pending "updates the sum"
		pending "tweets the current status, if necessary"
		
		after do
			SneakerBot.cron
		end
	end
end
