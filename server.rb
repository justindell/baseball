require 'sinatra'
require 'thin'
require 'mechanize'
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
  @players = Calculate.pitchers params
  erb :pitchers
end

get '/team' do
  @players = Calculate.team
  erb :team
end

post '/draft' do
  Calculate.draft params[:player_id]
  redirect back
end
