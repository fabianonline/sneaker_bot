class Webinterface < Sinatra::Base
	get '/help' do
		haml :help
	end
	
	get '/?:id?' do
		@sneak = Sneak.get(params[:id]) || Sneak.newest
		haml :main
	end
end
