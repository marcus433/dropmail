class StateController
  state: {}
  listeners: []
  constructor: (defaultState) ->
    @state = new Proxy defaultState,
      set: (target, prop, value) =>
        process.nextTick(=> @onChange(prop)) if target[prop] isnt value
        return Reflect.set(target, prop, value)
  onChange: (prop) =>
    window.requestAnimationFrame( =>
      next = (idx) =>
        return if idx < 0
        @listeners[idx](@state, prop)
        next(--idx)
      next(@listeners.length - 1)
    )
  addListener: (callback) =>
    @listeners.push(callback)
  removeListener: (callback) =>
    idx = @listeners.indexOf(callback)
    @listeners.splice(idx, 1) if idx > -1

module.exports = StateController
