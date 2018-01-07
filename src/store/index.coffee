StateController = require './state'
Collections = require './collections'
Selections = require './selection'
Actions = require './actions'
Notifications = require './notifications'
realm = require '../api/realm'

# TODO; set initial on callback from Folder & account listeenrs.
stateController = new StateController({
  unread: false
  tag: null
  search: null
  snoozed: false
  files: false
  folder: realm.objects('Folder').filtered('type == 1').find(-> true)
  accounts: realm.objects('Account')
})

collections = new Collections(stateController)
selections = new Selections(stateController, collections)
collections.addListener 'focus', selections.reset
actions = new Actions()

# NOTE: test function to play around with listener execution
###
  IDEA
  priority execution.

  eg could give list a 100ms higher priority than conversationsView
  for rendering
###
class unionListeners
  listeners: []
  timeout: null
  constructor: (listeners, @callback) ->
    for listener in listeners
      listener(@debounce)
  debounce: =>
    clearTimeout(@timeout)
    @timeout = setTimeout =>
      @callback()
    , 50
  removeListeners: =>
    for [listener, args...] in @listeners
      listener.removeListener(args..., @debounce) if listener.removeListener?
    @listeners = []
    clearTimeout(@timeout)

module.exports = {
  global: stateController
  collections
  selections
  actions
  unionListeners
}
