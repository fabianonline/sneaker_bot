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

	pending ".create"

	pending "#update_sum"
	
	describe "#double?" do
		it "returns true for sneaks at the beginning of the month" do
			Sneak.create(DateTime.new(2012, 5, 1)).double?.should be_true
			Sneak.create(DateTime.new(2012, 5, 7)).double?.should be_true
		end
		
		it "returns false for sneaks not at the beginning of the month" do
			Sneak.create(DateTime.new(2012, 5, 8)).double?.should be_false
			Sneak.create(DateTime.new(2012, 5, 17)).double?.should be_false
		end
	end
end
