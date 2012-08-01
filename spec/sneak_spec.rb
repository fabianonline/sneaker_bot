require File.dirname(__FILE__) + '/spec_helper'

describe "Sneak" do
	describe ".newest" do
		describe "when there is no Sneak yet" do
			it "creates a new Sneak" do
				Sneak.should_receive(:create)
				Sneak.newest
			end

			it "returns a Sneak" do
				Sneak.newest.should be_a Sneak
			end
		end

		it "returns the newest sneak if there is one" do
			@sneak_1 = Sneak.create(DateTime.new(2012, 05, 01))
			@sneak_2 = Sneak.create(DateTime.new(2012, 05, 02))
			Sneak.should_not_receive(:create)
			Sneak.newest.should == @sneak_2
		end
	end

	describe ".create" do
		it "sets bonus_points correctly" do
			Sneak.create(DateTime.new(2012, 5, 1)).bonus_points.should == 2
			Sneak.create(DateTime.new(2012, 5, 8)).bonus_points.should == 1
		end
		
		it "sets variant correctly" do
			Sneak.create(DateTime.new(2012, 5, 1)).variant.should == "double"
			Sneak.create(DateTime.new(2012, 5, 8)).variant.should == "single"
		end
	end

	pending "#update_sum"
	
	describe "#double?" do
		it "returns true for sneaks with type 'single'" do
			s = Sneak.newest
			s.should_receive(:variant).and_return("double")
			s.double?.should be_true
		end
		
		it "returns false for sneaks with type 'double'" do
			s = Sneak.newest
			s.should_receive(:variant).and_return("single")
			s.double?.should be_false
		end
	end
end
