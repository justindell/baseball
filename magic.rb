require 'date'
require 'gchart'

MAGIC_NUMBER = 1
SIMULATIONS = 100000

@cubs_win   = [65,69,68,72,66,73,64,64,66,61,53,63,57,57,62,62,62]
@cards_lose = [55,51,53,53,50,46,39,64,66,62,37,36,38,38,43,43,43]

def run_season magic
  day = Date.today + 1
  while magic > 0 && day <= Date.today + 7
    magic -= 1 if (@cubs_win.shift || 50) > rand(100) + 1
    magic -= 1 if (@cards_lose.shift || 50) > rand(100) + 1
    day += 1 if magic > 0
  end
  day
end

days = []
SIMULATIONS.times do
  days << run_season(MAGIC_NUMBER)
end

chart_data = Hash.new 0
days.each do |day|
  chart_data[day] += 1
end

total = chart_data.map(&:last).inject(&:+)
chart_data.sort.each do |d,i|
  puts "#{d.to_s}: #{((i / total.to_f) * 100).round(3)}%"
end

chart_data = chart_data.sort.take(10)

g = Gchart.bar title: 'Potential Cubs Clinch Days', data: chart_data.map(&:last), axis_with_labels: 'x', axis_labels: [chart_data.map(&:first).map { |d| "#{d.month}/#{d.day}" }.join('|')], size: '800x300', bar_colors: '0E3386'

puts g
