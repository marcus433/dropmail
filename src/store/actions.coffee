class Actions
  actions: {}
  dispatch: (name, args) =>
    window.requestAnimationFrame( =>
      for listener in @actions[name]
        listener(args...)
    )
    return
  addListener: (name, callback) =>
    @actions[name] ?= []
    @actions[name].push(callback)
  removeListener: (name, callback) =>
    idx = @actions[name].indexOf(callback)
    @actions[name].splice(idx, 1) if idx > -1

module.exports = Actions
