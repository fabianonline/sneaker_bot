require File.dirname(__FILE__) + '/spec_helper'

describe Participation do
	describe "#to_s_short" do
		before do
			@user = User.create(:username=>"hz", :twitter_id=>"1234", :alias=>"Heinz", :id=>42, :reminder_ignored=>0, :bonus_points=>1)
			@sneak = Sneak.newest
			@part = Participation.new(:sneak=>@sneak, :text=>"ja", :sum=>1, :psp=>false, :frei=>false, :time=>DateTime.now, :user=>@user)
		end
		
		subject {@part.to_s_short }
		
		it "formats normal Participations correctly" do
			should == "Heinz"
		end
		
		it "formats participations with guests correctly" do
			@part.sum = 3
			should == "Heinz +2"
		end
		
		it "formats participations with flag 'PSP' correctly" do
			@part.psp = true
			should == "Heinz [P]"
		end
		
		it "formats participations with flag 'Freikarte' correctly" do
			@part.frei = true
			should == "Heinz [F]"
		end
		
		it "formats participations with multiple special flags correctly" do
			@part.sum = 7
			@part.psp = true
			@part.frei = true
			should == "Heinz +6 [F,P]"
		end
		
		describe "if a user has enough bonus points" do
			before do
				@user.bonus_points = 5
			end
			
			it "adds a B flag for normal sneaks" do
				@sneak.should_receive(:double?).and_return(false)
				should == "Heinz [B]"
			end
			
			it "does not add a B flag for double sneaks" do
				@sneak.should_receive(:double?).and_return(true)
				should == "Heinz"
			end
		end
	end
end