require 'twitter'
require 'yaml'

client = Twitter::REST::Client.new do |config|
  config.consumer_key    = 'wSrIn3sAkd1O2lkTv4M9SDsjl'
  config.consumer_secret = 'wR7pOFN8fHezr7mHazDsv9f18z1pQWKZJcPGsJpugp2WcsyEEz'
end


def collect_with_max_id(collection=[], max_id=nil, &block)
  response = yield(max_id)
  collection += response
  response.empty? ? collection.flatten : collect_with_max_id(collection, response.last.id - 1, &block)
end

def client.get_all_tweets(user)
  collect_with_max_id do |max_id|
    options = {count: 200, include_rts: true}
    options[:max_id] = max_id unless max_id.nil?
    user_timeline(user, options)
  end
end

File.write('tweets.yml', YAML.dump(client.get_all_tweets("MLBReplays")))
