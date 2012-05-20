class Webinterface < Sinatra::Base
	get '/?:id?' do
		@sneak = Sneak.get(params[:id]) || Sneak.newest
		haml :main
	end
end
