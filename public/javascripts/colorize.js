var tier = 1;
var counter = 0;

function determineColor(value, next, length) {
  switch(tier) {
    case 1: color = "red"; break;
    case 2: color = "orange"; break;
    case 3: color = "green"; break;
    case 4: color = "blue"; break;
    default: color = "black";
  }
  if ((value - next) > 1.5 || (counter > (length / 10))) {
    tier++;
    counter = 0;
  } else {
    counter++;
  }
  return color;
}

$(document).ready(function() {
  length = $('tbody tr').length
  for (i=0;i<length-1;i++) {
    player = $('tbody tr')[i]
    playerVal = parseFloat(player.children[3].innerHTML);
    nextVal = parseFloat($('tbody tr')[i+1].children[3].innerHTML);
    color = determineColor(playerVal, nextVal, length);
    $(player).addClass(color);
  }
});

