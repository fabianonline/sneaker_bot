class Webinterface < Sinatra::Base
	get '/help' do
		haml :help
	end
	
	get '/?:id?' do
		@sneak = Sneak.get(params[:id]) || Sneak.newest
		@prev_sneak = Sneak.get(@sneak.id - 1)
		@next_sneak = Sneak.get(@sneak.id + 1)
		haml :main
	end
end
