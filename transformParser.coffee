###
  transform: rotate(15deg) translateX(230px)  scale(1.5, 2.6) skew(220deg, -150deg)
###
var translate = function(node, x, y) {
  // Credit to http://stackoverflow.com/users/1336843/bali-balo for the matrix regex.
  if (window.getComputedStyle) {
    node = window.getComputedStyle(node);
    var transform = node.transform || node.webkitTransform || node.mozTransform;
    if (!transform || 0 === transform.length)
      return "translate3d(" + (x || 0) + "px, " + (y || 0) + "px, 0px)";
    if (node = transform.match(/^matrix3d\((.+)\)$/)) {
      node = node[1].split(",");
      node[12] = (parseFloat(node[12]) || 0) + x;
      node[13] = (parseFloat(node[13]) || 0) + y;
      return "matrix(" + node.join(",") + ")";
    }
    if (node = transform.match(/^matrix\((.+)\)$/)) {
      node = node[1].split(",");
      node[4] = (parseFloat(node[4]) || 0) + x;
      node[5] = (parseFloat(node[5]) || 0) + y;
      return "matrix(" + node.join(",") + ")";
    }
  }
};
