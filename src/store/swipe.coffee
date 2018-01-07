class SwipePositionController
  state: 0
  type: null
  listeners: []
  setPosition: (@state, @type) =>
    @onChange()
  onChange: =>
    # TODO: issues when selection multiple, but makes aniamtion buttery smooth
    #window.requestAnimationFrame( =>
    next = (idx) =>
      return if idx < 0
      @listeners[idx](@state, @type)
      next(--idx)
    next(@listeners.length - 1)
    #)
  addListener: (callback) =>
    @listeners.push(callback)
  removeListener: (callback) =>
    idx = @listeners.indexOf(callback)
    @listeners.splice(idx, 1) if idx > -1

module.exports = new SwipePositionController()
