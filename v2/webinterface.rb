class Webinterface < Sinatra::Base
	get '/' do
		haml :main
	end
end
