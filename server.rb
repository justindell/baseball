require 'sinatra'
require 'thin'
require './calculate'

set(:css_dir) { File.join(views, 'css') }

get '/' do
  @players = Calculate.players params
  erb :index
end

get '/batters' do
  @players = Calculate.batters params
  erb :batters
end

get '/pitchers' do
  @players = Calculate.pitchers
  erb :pitchers
end

post '/draft' do
  Calculate.draft params[:player_id] 
  redirect to('/')
end
