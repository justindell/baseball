require 'date'
require 'gchart'

MAGIC_NUMBER = 16
SIMULATIONS = 100000

@cubs_win   = [57,67,60,59,64,62,68,58,53,55,50,56,53,69,69,69,69,67,67,67,60,60,60,53,53,53,53,61,61,61]
@cards_lose = [49,47,43,54,52,55,44,32,35,40,50,56,53,53,53,53,53,49,48,48,60,60,60,39,39,39,39,46,46,46]

@games_day = [1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]

def run_season magic
  games = 0
  while magic > 0
    if games % 2 == 0
      magic -= 1 if (@cubs_win.shift || 50) > rand(100) + 1
    else
      magic -= 1 if (@cards_lose.shift || 50) > rand(100) + 1
    end
    games += 1
  end
  games
end

def to_day(games)
  start_date = Date.today
  games_day = @games_day.dup
  while games > 0
    today = (games_day.shift || 1)
    start_date += 1
    games -= today
  end
  start_date
end

results = []
days = []
SIMULATIONS.times do
  result = run_season(MAGIC_NUMBER)
  results << result
  days << to_day(result)
end

games = results.inject(:+) / results.count.to_f

puts "#{games.to_i} games"
puts "clinch on #{to_day(games).to_s}"

chart_data = Hash.new 0
days.each do |day|
  chart_data[day] += 1
end

chart_data = chart_data.sort.take(@games_day.count - 10)

g = Gchart.bar title: 'Potential Cubs Clinch Days', data: chart_data.map(&:last), axis_with_labels: 'x', axis_labels: [chart_data.map(&:first).map { |d| "#{d.month}/#{d.day}" }.join('|')], size: '800x300', bar_colors: '0E3386'

puts g.inspect
