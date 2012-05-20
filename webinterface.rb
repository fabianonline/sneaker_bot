class Webinterface < Sinatra::Base
	get '/?:id?' do
		@sneak = Sneak.first(params[:id]) || Sneak.newest
		haml :main
	end
end
