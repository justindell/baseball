var BASEBALL = BASEBALL || {}

BASEBALL.chartData = [];
BASEBALL.allCategories = {'batters': ['R', 'HR', 'RBI', 'SB', 'AVG', 'OBP'],
                       'pitchers': ['SO', 'SV', 'ERA', 'H/9', 'BB/9', 'QS']};

BASEBALL.initialize = function(position) {
  BASEBALL.categories = BASEBALL.allCategories[position];
  $('.player-name').click(BASEBALL.drawChart);
  $('#clear-chart').click(BASEBALL.clearChart);
}

BASEBALL.chartVal = function(row, index) {
  value = row[index].innerHTML;
  return parseFloat(value) > 3 ? 3 : parseFloat(value);
}

BASEBALL.drawChart = function(e) {
  var row = $(e.target).parent().parent().find('td');
  BASEBALL.chartData.push({
    axes: [
      {axis: BASEBALL.categories[0], value: BASEBALL.chartVal(row, 11)},
      {axis: BASEBALL.categories[1], value: BASEBALL.chartVal(row, 12)},
      {axis: BASEBALL.categories[2], value: BASEBALL.chartVal(row, 13)},
      {axis: BASEBALL.categories[3], value: BASEBALL.chartVal(row, 14)},
      {axis: BASEBALL.categories[4], value: BASEBALL.chartVal(row, 15)},
      {axis: BASEBALL.categories[5], value: BASEBALL.chartVal(row, 16)}
    ]});
  RadarChart.draw("#radar", BASEBALL.chartData, {radius: 3, w: 300, h: 300});
  $('#clear-chart').show();
};

BASEBALL.clearChart = function() {
  BASEBALL.chartData = [];
  $('#radar').empty();
  $('#clear-chart').hide();
}
